// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * NexoraProfitVault v0.2 - UN-AUDITED TESTNET PROTOTYPE.
 *
 * Holds user principal separately from operator-funded rewards.
 * Allocations are NOT automatic, guaranteed, or proofs of trading profit:
 * an authorized allocator must submit an independently reviewable report ID.
 * No strategy integrations, leverage, principal lending, or admin withdrawals.
 */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NexoraProfitVault is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant FUNDER_ROLE = keccak256("FUNDER_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    uint256 public constant UNIT = 1e18; // BNB Chain Binance-Peg USDT uses 18 decimals
    uint256 public constant MIN_DEPOSIT = 10 * UNIT;
    uint256 public constant MIN_ACTIVE_DIRECT = 100 * UNIT;
    uint256 public constant MAX_PERSONAL_CAPITAL = 50_000 * UNIT;
    uint256 public constant MATURITY = 1 days; // rank qualification only
    uint256 public constant WITHDRAWAL_LOCK = 90 days;
    uint256 public constant WITHDRAWAL_WINDOW = 1 days;
    uint256 public constant MAX_WITHDRAWAL_BPS = 2_000; // 20% each anchored 24h window
    uint256 public constant WITHDRAWAL_FEE_BPS = 0; // explicit no-fee withdrawals
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_DIRECT_CHILDREN = 128;

    IERC20 public immutable asset;

    struct Account {
        address referrer;           // permanent: assigned on first deposit only
        uint256 principal;          // user-owned, never available for rewards
        uint256 baseRewards;        // fully funded, claimable
        uint256 referralRewards;    // fully funded, claimable
        uint256 lastDepositAt;      // ALL deposits reset 24h eligibility
        uint256 firstDepositAt;     // reward lock begins at FIRST deposit
        uint256 lastCreditAt;       // minimum 24h between allocations
        uint32 activeDirects;       // updated through syncDirect()
        bool everDeposited;
        bool countedInParent;
    }

    struct PrincipalTranche {
        uint256 remaining;
        uint64 unlockAt;
    }
    struct WithdrawalWindow {
        uint64 startedAt;
        uint256 spentGross;
    }

    mapping(address => PrincipalTranche[]) private _principalTranches;
    mapping(address => uint256) private _nextTranche;
    mapping(address => WithdrawalWindow) public withdrawalWindows;
    mapping(address => uint256) public externalDepositBasis; // excludes Reinvest
    mapping(address => Account) private _accounts;
    mapping(address => address[]) private _children;
    mapping(address => uint256) public teamVolume; // 3-level active principal
    mapping(address => mapping(address => uint256)) public branchVolume;
    mapping(bytes32 => bool) public usedReportIds;

    uint256 public totalPrincipal;
    uint256 public unallocatedRewards;
    uint256 public totalClaimableRewards;

    event Joined(address indexed member, address indexed referrer);
    event Deposited(address indexed member, uint256 amount, uint256 totalPrincipalOfMember);
    event PrincipalWithdrawn(address indexed member, uint256 amount);
    event Reinvested(address indexed member, uint256 amount, uint256 unlockAt);
    event WithdrawalWindowUsed(address indexed member, uint256 grossAmount, uint256 windowStartedAt);
    event WithdrawalPolicy(address indexed member, uint256 grossAmount, uint256 feeAmount);
    event DirectSynced(address indexed member, address indexed parent, bool counted);
    event RewardPoolFunded(address indexed funder, uint256 amount);
    event RewardAllocated(address indexed member, bytes32 indexed reportId, uint256 baseAmount, uint256 referralTotal, uint16 tierBps);
    event ReferralReward(address indexed earner, address indexed fromMember, uint8 level, uint256 amount);
    event RewardClaimed(address indexed member, uint256 amount);

    error ZeroAddress();
    error InvalidAsset();
    error InvalidAmount();
    error InvalidReferrer();
    error TooManyDirects();
    error ExceedsCapitalLimit();
    error NotMature();
    error NotEligible();
    error AlreadyQualified();
    error CreditTooSoon();
    error ExceedsDailyCap();
    error InvalidOrUsedReport();
    error InsufficientRewardPool();
    error FeeOnTransferNotSupported();
    error InsufficientPrincipal();
    error WithdrawalLimitExceeded();
    error NoMaturedTranche();

    constructor(address token_, address admin_, address funder_, address allocator_) {
        if (token_ == address(0) || admin_ == address(0) ||
            funder_ == address(0) || allocator_ == address(0)) revert ZeroAddress();
        if (token_.code.length == 0 || IERC20Metadata(token_).decimals() != 18) {
            revert InvalidAsset();
        }
        asset = IERC20(token_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(GUARDIAN_ROLE, admin_);
        _grantRole(FUNDER_ROLE, funder_);
        _grantRole(ALLOCATOR_ROLE, allocator_);
    }

    /**
     * Deposit and optionally set a permanent referrer.
     * A referrer must have deposited BEFORE this account's first deposit.
     * This chronological rule prevents cycles without an expensive ancestry walk.
     */
    function deposit(uint256 amount, address referrer_) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();
        Account storage a = _accounts[msg.sender];
        uint256 afterDeposit = a.principal + amount;
        if (afterDeposit > MAX_PERSONAL_CAPITAL) revert ExceedsCapitalLimit();
        if (!a.everDeposited) {
            if (afterDeposit < MIN_DEPOSIT) revert InvalidAmount();
            if (referrer_ != address(0)) {
                if (referrer_ == msg.sender || !_accounts[referrer_].everDeposited) {
                    revert InvalidReferrer();
                }
                if (_children[referrer_].length >= MAX_DIRECT_CHILDREN) {
                    revert TooManyDirects();
                }
                a.referrer = referrer_;
                _children[referrer_].push(msg.sender);
            }
            a.everDeposited = true;
            a.firstDepositAt = block.timestamp;
            emit Joined(msg.sender, referrer_);
        } else if (referrer_ != address(0) && referrer_ != a.referrer) {
            revert InvalidReferrer();
        }

        uint256 balanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) - balanceBefore != amount) {
            revert FeeOnTransferNotSupported();
        }

        if (a.countedInParent) {
            a.countedInParent = false;
            --_accounts[a.referrer].activeDirects;
            emit DirectSynced(msg.sender, a.referrer, false);
        }

        a.principal = afterDeposit;
        a.lastDepositAt = block.timestamp;
        externalDepositBasis[msg.sender] += amount;
        _principalTranches[msg.sender].push(PrincipalTranche(amount, uint64(block.timestamp + WITHDRAWAL_LOCK)));
        totalPrincipal += amount;
        _updateTeamVolume(msg.sender, amount, true);
        emit Deposited(msg.sender, amount, afterDeposit);
    }

    /**
     * Withdraw only a user's OWN matured principal after 90 days.
     * Gross withdrawals and reward claims share a 20% cap of lifetime
     * external deposits per anchored 24-hour window; all fees are ZERO.
     * No owner, admin, funder, allocator or company partner can call
     * this function on someone else's behalf.
     */
    function withdrawPrincipal(uint256 amount) external nonReentrant {
        Account storage a = _accounts[msg.sender];
        if (amount == 0) revert InvalidAmount();
        if (a.principal < amount) revert InsufficientPrincipal();

        _consumeWithdrawalCap(msg.sender, amount);
        _consumeMaturedPrincipal(msg.sender, amount);

        a.principal -= amount;
        totalPrincipal -= amount;
        _updateTeamVolume(msg.sender, amount, false);

        if (a.principal < MIN_ACTIVE_DIRECT && a.countedInParent) {
            a.countedInParent = false;
            --_accounts[a.referrer].activeDirects;
            emit DirectSynced(msg.sender, a.referrer, false);
        }

        asset.safeTransfer(msg.sender, amount);
        emit WithdrawalPolicy(msg.sender, amount, 0);
        emit PrincipalWithdrawn(msg.sender, amount);
    }

    /**
     * Move already funded, credited rewards into a NEW 90-day principal
     * tranche (no ERC20 transfer and no fee). This does not increase
     * externalDepositBasis or the maximum 20% withdrawal allowance.
     */
    function reinvestRewards(uint256 amount) external whenNotPaused nonReentrant {
        Account storage a = _accounts[msg.sender];
        if (!a.everDeposited || amount == 0 || amount > a.baseRewards + a.referralRewards) {
            revert InvalidAmount();
        }
        if (a.principal + amount > MAX_PERSONAL_CAPITAL) revert ExceedsCapitalLimit();

        uint256 baseConsumed = a.baseRewards < amount ? a.baseRewards : amount;
        a.baseRewards -= baseConsumed;
        a.referralRewards -= (amount - baseConsumed);
        totalClaimableRewards -= amount;

        if (a.countedInParent) {
            a.countedInParent = false;
            --_accounts[a.referrer].activeDirects;
            emit DirectSynced(msg.sender, a.referrer, false);
        }
        a.principal += amount;
        totalPrincipal += amount;
        a.lastDepositAt = block.timestamp;
        uint64 unlockAt = uint64(block.timestamp + WITHDRAWAL_LOCK);
        _principalTranches[msg.sender].push(PrincipalTranche(amount, unlockAt));
        _updateTeamVolume(msg.sender, amount, true);
        emit Reinvested(msg.sender, amount, unlockAt);
    }

    function remainingWithdrawalCap(address user) public view returns (uint256) {
        uint256 limit = externalDepositBasis[user] * MAX_WITHDRAWAL_BPS / BPS;
        WithdrawalWindow storage w = withdrawalWindows[user];
        if (w.startedAt == 0 || block.timestamp >= uint256(w.startedAt) + WITHDRAWAL_WINDOW) {
            return limit;
        }
        return w.spentGross >= limit ? 0 : limit - w.spentGross;
    }

    function principalTrancheCount(address user) external view returns (uint256) {
        return _principalTranches[user].length;
    }

    function principalTrancheAt(address user, uint256 i)
        external view returns (uint256 remaining, uint64 unlockAt)
    {
        PrincipalTranche storage t = _principalTranches[user][i];
        return (t.remaining, t.unlockAt);
    }

    function _consumeWithdrawalCap(address user, uint256 amount) private {
        WithdrawalWindow storage w = withdrawalWindows[user];
        if (amount > remainingWithdrawalCap(user)) revert WithdrawalLimitExceeded();
        if (w.startedAt == 0 || block.timestamp >= uint256(w.startedAt) + WITHDRAWAL_WINDOW) {
            w.startedAt = uint64(block.timestamp);
            w.spentGross = 0;
        }
        w.spentGross += amount;
        emit WithdrawalWindowUsed(user, amount, w.startedAt);
    }

    function _consumeMaturedPrincipal(address user, uint256 amount) private {
        PrincipalTranche[] storage list = _principalTranches[user];
        uint256 i = _nextTranche[user];
        uint256 needed = amount;

        // Tranches are added with monotonically increasing unlock times,
        // so it is safe to stop at the first immature tranche.
        while (needed != 0 && i < list.length) {
            PrincipalTranche storage t = list[i];
            if (block.timestamp < t.unlockAt) break;
            uint256 used = t.remaining < needed ? t.remaining : needed;
            t.remaining -= used;
            needed -= used;
            if (t.remaining != 0) break;
            ++i;
        }
        if (needed != 0) revert NoMaturedTranche();
        _nextTranche[user] = i;
    }

    /**
     * Permissionless sync AFTER 24h. Called by a user, sponsor, or keeper.
     * Top-ups reset the qualification timer and undo the previous count.
     */
    function syncDirect(address member) external {
        Account storage a = _accounts[member];
        if (a.referrer == address(0) || a.principal < MIN_ACTIVE_DIRECT) {
            revert NotEligible();
        }
        if (block.timestamp < a.lastDepositAt + MATURITY) revert NotMature();
        if (a.countedInParent) revert AlreadyQualified();
        a.countedInParent = true;
        ++_accounts[a.referrer].activeDirects;
        emit DirectSynced(member, a.referrer, true);
    }

    /**
     * Funds rewards with NEW tokens from an authorized non-user funding wallet.
     * Principal never becomes part of this pool. Funding is irreversible.
     * The contract cannot independently verify the economic source of funds.
     */
    function fundRewards(uint256 amount) external onlyRole(FUNDER_ROLE) nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) - beforeBalance != amount) {
            revert FeeOnTransferNotSupported();
        }
        unallocatedRewards += amount;
        emit RewardPoolFunded(msg.sender, amount);
    }

    /**
     * Authorized, fully funded allocation. Not an automated daily entitlement.
     * Cap = 1/1.25/1.5/2/2.5% of eligible principal for this 24h period.
     * Up to 25% on top is reserved for eligible 3-level referrers (15/7/3).
     * A reportId should identify externally verifiable performance evidence.
     */
    function allocateReward(address member, uint256 amount, bytes32 reportId)
        external onlyRole(ALLOCATOR_ROLE) whenNotPaused nonReentrant
    {
        if (member == address(0) || amount == 0) revert InvalidAmount();
        if (reportId == bytes32(0) || usedReportIds[reportId]) revert InvalidOrUsedReport();

        Account storage a = _accounts[member];
        uint16 rate = tierBps(member);
        if (rate == 0) revert NotEligible();
        if (a.lastCreditAt != 0 && block.timestamp < a.lastCreditAt + MATURITY) {
            revert CreditTooSoon();
        }
        if (amount > a.principal * rate / BPS) revert ExceedsDailyCap();

        address[3] memory earners;
        uint256[3] memory bonuses;
        uint256 cost = amount;
        address ancestor = a.referrer;

        for (uint8 level = 0; level < 3 && ancestor != address(0); ++level) {
            if (_qualifiedReferrer(ancestor)) {
                uint256 bps = level == 0 ? 1_500 : (level == 1 ? 700 : 300);
                uint256 bonus = amount * bps / BPS;
                earners[level] = ancestor;
                bonuses[level] = bonus;
                cost += bonus;
            }
            ancestor = _accounts[ancestor].referrer;
        }

        if (unallocatedRewards < cost) revert InsufficientRewardPool();
        usedReportIds[reportId] = true;
        a.lastCreditAt = block.timestamp;
        unallocatedRewards -= cost;
        totalClaimableRewards += cost;
        a.baseRewards += amount;
        for (uint8 level = 0; level < 3; ++level) {
            if (bonuses[level] == 0) continue;
            _accounts[earners[level]].referralRewards += bonuses[level];
            emit ReferralReward(earners[level], member, level + 1, bonuses[level]);
        }
        emit RewardAllocated(member, reportId, amount, cost - amount, rate);
    }

    /**
     * Claim backed reward only AFTER 90 days from the account's first
     * external deposit. Claims share the same 20% withdrawal cap window.
     * If claimable rewards exceed remaining capacity, only the permitted
     * portion is claimed; the rest remains safely credited and backed.
     */
    function claimRewards() external nonReentrant returns (uint256 amount) {
        Account storage a = _accounts[msg.sender];
        if (!a.everDeposited || block.timestamp < a.firstDepositAt + WITHDRAWAL_LOCK) {
            revert NotMature();
        }
        uint256 available = a.baseRewards + a.referralRewards;
        if (available == 0) revert InvalidAmount();
        uint256 limit = remainingWithdrawalCap(msg.sender);
        if (limit == 0) revert WithdrawalLimitExceeded();
        amount = available < limit ? available : limit;
        _consumeWithdrawalCap(msg.sender, amount);
        uint256 baseConsumed = a.baseRewards < amount ? a.baseRewards : amount;
        a.baseRewards -= baseConsumed;
        a.referralRewards -= (amount - baseConsumed);
        totalClaimableRewards -= amount;
        asset.safeTransfer(msg.sender, amount);
        emit WithdrawalPolicy(msg.sender, amount, 0);
        emit RewardClaimed(msg.sender, amount);
    }

    function tierBps(address member) public view returns (uint16) {
        Account storage a = _accounts[member];
        if (a.principal < MIN_DEPOSIT || a.lastDepositAt == 0 ||
            block.timestamp < a.lastDepositAt + MATURITY) return 0;

        if (a.activeDirects < 2 || teamVolume[member] < 2_500 * UNIT) return 100;
        if (!_hasBalancedBranches(member)) return 100;

        uint256 c = a.principal;
        uint256 d = a.activeDirects;
        uint256 v = teamVolume[member];
        if (c >= 25_000 * UNIT && d >= 10 && v >= 125_000 * UNIT) return 250;
        if (c >= 10_000 * UNIT && d >= 6 && v >= 50_000 * UNIT) return 200;
        if (c >= 2_500 * UNIT && d >= 4 && v >= 12_500 * UNIT) return 150;
        if (c >= 500 * UNIT && d >= 2 && v >= 2_500 * UNIT) return 125;
        return 100;
    }

    function _qualifiedReferrer(address referrer_) internal view returns (bool) {
        Account storage a = _accounts[referrer_];
        return a.principal >= MIN_ACTIVE_DIRECT && a.lastDepositAt != 0 &&
            block.timestamp >= a.lastDepositAt + MATURITY;
    }

    function _hasBalancedBranches(address member) internal view returns (bool) {
        uint256 volume = teamVolume[member];
        if (volume == 0) return false;
        address[] storage children = _children[member];
        uint256 largest;
        for (uint256 i; i < children.length; ++i) {
            uint256 b = branchVolume[member][children[i]];
            if (b > largest) largest = b;
        }
        return largest * 2 <= volume;
    }

    function _updateTeamVolume(address member, uint256 amount, bool increase) internal {
        address parent = _accounts[member].referrer;
        address branch = member;
        for (uint8 depth; depth < 3 && parent != address(0); ++depth) {
            if (increase) {
                teamVolume[parent] += amount;
                branchVolume[parent][branch] += amount;
            } else {
                teamVolume[parent] -= amount;
                branchVolume[parent][branch] -= amount;
            }
            branch = parent;
            parent = _accounts[parent].referrer;
        }
    }

    function directCount(address user) external view returns (uint256) {
        return _children[user].length;
    }

    function directAt(address user, uint256 index) external view returns (address) {
        return _children[user][index];
    }

    function getAccount(address user) external view returns (Account memory) {
        return _accounts[user];
    }

    /**
     * True when the vault's actual token balance backs all principal and
     * reward liabilities, excluding unsolicited token transfers.
     */
    function isSolvent() external view returns (bool) {
        return asset.balanceOf(address(this)) >=
            totalPrincipal + unallocatedRewards + totalClaimableRewards;
    }

    // Pause blocks new deposits/allocations/reinvests, NOT matured withdrawals/claims.
    function pause() external onlyRole(GUARDIAN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
