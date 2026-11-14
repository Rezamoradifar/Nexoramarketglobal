// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Nexora Model 2 shared accounting - UN-AUDITED CANDIDATE.
 * Gross paid-in history and the gross plan reference are NOT redeemable capital.
 * Each deposit/reinvest explicitly allocates 20% (6% owner, 1.4% x 10 companies).
 * Only the remaining 80% becomes backed user principal. Rewards need a separate
 * funded reserve; the contract cannot independently prove economic profits.
 * No admin principal withdrawal, trading integration or guaranteed returns.
 */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {NexoraRevenueSplitter} from "./NexoraRevenueSplitter.sol";

abstract contract NexoraModel2Core is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    bytes32 public constant FUNDER_ROLE = keccak256("FUNDER_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    uint256 public constant UNIT = 1e18;
    uint256 public constant MIN_DEPOSIT = 10 * UNIT;
    uint256 public constant MIN_ACTIVE_DIRECT = 100 * UNIT;
    uint256 public constant MAX_PERSONAL_CAPITAL = 50_000 * UNIT;
    uint256 public constant MATURITY = 1 days;
    uint256 public constant WITHDRAWAL_LOCK = 90 days;
    uint256 public constant WITHDRAWAL_WINDOW = 1 days;
    uint256 public constant MAX_WITHDRAWAL_BPS = 2_000;
    uint256 public constant WITHDRAWAL_FEE_BPS = 0;
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_DIRECT_CHILDREN = 128;
    uint256 public constant ENTRY_COMPANY_BPS = 2_000;

    IERC20 public immutable asset;
    NexoraRevenueSplitter public immutable companySplitter;
    uint256 public distributionNonce;

    struct Account {
        address referrer;
        uint256 principal; // NET backed capital, not gross receipt
        uint256 baseRewards;
        uint256 referralRewards;
        uint256 lastDepositAt;
        uint256 firstDepositAt;
        uint256 grossPositionBasis; // nonredeemable open plan reference
        uint256 grossDepositsLifetime; // historical external receipts
        uint256 lastCreditAt;
        uint32 activeDirects;
        bool everDeposited;
        bool countedInParent;
    }
    struct PrincipalTranche {
        uint256 remaining;
        uint64 unlockAt;
        uint256 grossRemaining;
    }
    // Ordered cumulative checkpoints give exact rolling-24h accounting with
    // O(log n) lookups, rather than scanning every historical withdrawal.
    // Multiple withdrawals with the same timestamp share one checkpoint.
    struct WithdrawalCheckpoint {
        uint64 timestamp;
        uint256 cumulativeGross;
    }
    mapping(address => PrincipalTranche[]) private _principalTranches;
    mapping(address => uint256) private _nextTranche;
    mapping(address => WithdrawalCheckpoint[]) private _withdrawalCheckpoints;
    mapping(address => uint256) public externalDepositBasis; // excludes Reinvest
    mapping(address => Account) private _accounts;
    mapping(address => address[]) private _children;
    mapping(address => uint256) public teamVolume; // 3-level open gross plan basis, not net principal
    mapping(address => mapping(address => uint256)) public branchVolume;
    mapping(bytes32 => bool) public usedReportIds;
    uint256 public totalPrincipal;
    uint256 public unallocatedRewards;
    uint256 public totalClaimableRewards;

    event Joined(address indexed member, address indexed referrer);
    event Deposited(address indexed member, uint256 amount, uint256 totalPrincipalOfMember);
    event PrincipalWithdrawn(address indexed member, uint256 amount);
    event Reinvested(address indexed member, uint256 amount, uint256 unlockAt);
    event Model2Entry(address indexed member, bool indexed reinvest, bytes32 indexed evidenceId,
        uint256 grossAmount, uint256 netPrincipalCredited, uint256 companyAllocation,
        uint256 grossOpenPositionBasis);
    event WithdrawalWindowUsed(address indexed member, uint256 grossAmount, uint256 windowStartedAt);
    event WithdrawalPolicy(address indexed member, uint256 grossAmount, uint256 feeAmount);
    event DirectSynced(address indexed member, address indexed parent, bool counted);
    event RewardPoolFunded(address indexed funder, uint256 amount);
    event RewardAllocated(address indexed member, bytes32 indexed reportId, uint256 baseAmount,
        uint256 referralTotal, uint16 tierBps);
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
    error IncorrectSplitter();
    error TestnetOnly(uint256 actualChainId);
    error MainnetOnly(uint256 actualChainId);

    constructor(address token_, address admin_, address funder_, address allocator_, address splitter_, uint256 allowedChainId_) {
        if (block.chainid != allowedChainId_) {
            if (allowedChainId_ == 97) revert TestnetOnly(block.chainid);
            revert MainnetOnly(block.chainid);
        }
        if (token_ == address(0) || admin_ == address(0) || funder_ == address(0) || allocator_ == address(0))
            revert ZeroAddress();
        if (token_.code.length == 0 || IERC20Metadata(token_).decimals() != 18) revert InvalidAsset();
        if (splitter_ == address(0) || splitter_.code.length == 0 ||
            address(NexoraRevenueSplitter(splitter_).asset()) != token_) revert IncorrectSplitter();
        asset = IERC20(token_);
        companySplitter = NexoraRevenueSplitter(splitter_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(GUARDIAN_ROLE, admin_);
        _grantRole(FUNDER_ROLE, funder_);
        _grantRole(ALLOCATOR_ROLE, allocator_);
    }

    /** A sponsor must have joined earlier; permanent chronological parents prevent cycles. */
    function deposit(uint256 amount, address referrer_) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();
        Account storage a = _accounts[msg.sender];
        uint256 netAmount = amount - amount / 5;
        uint256 afterDeposit = a.principal + netAmount;
        uint256 afterGross = a.grossPositionBasis + amount;
        if (afterGross > MAX_PERSONAL_CAPITAL) revert ExceedsCapitalLimit();
        if (!a.everDeposited) {
            if (afterGross < MIN_DEPOSIT) revert InvalidAmount();
            if (referrer_ != address(0)) {
                if (referrer_ == msg.sender || !_accounts[referrer_].everDeposited) revert InvalidReferrer();
                if (_children[referrer_].length >= MAX_DIRECT_CHILDREN) revert TooManyDirects();
                a.referrer = referrer_;
                _children[referrer_].push(msg.sender);
            }
            a.everDeposited = true;
            a.firstDepositAt = block.timestamp;
            emit Joined(msg.sender, referrer_);
        } else if (referrer_ != address(0) && referrer_ != a.referrer) {
            revert InvalidReferrer();
        }
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) - beforeBalance != amount) revert FeeOnTransferNotSupported();
        if (a.countedInParent) {
            a.countedInParent = false;
            --_accounts[a.referrer].activeDirects;
            emit DirectSynced(msg.sender, a.referrer, false);
        }
        a.principal = afterDeposit;
        a.grossPositionBasis = afterGross;
        a.grossDepositsLifetime += amount;
        a.lastDepositAt = block.timestamp;
        externalDepositBasis[msg.sender] += amount;
        _principalTranches[msg.sender].push(PrincipalTranche(netAmount,
            uint64(block.timestamp + WITHDRAWAL_LOCK), amount));
        totalPrincipal += netAmount;
        _updateTeamVolume(msg.sender, amount, true);
        // Record complete account effects before calling the splitter. A
        // splitter-funding callback sees the updated ledger; a revert rolls back
        // both the ledger and the incoming token transfer atomically.
        bytes32 evidenceId = _allocateCompanyShare(amount, false);
        emit Deposited(msg.sender, amount, afterDeposit);
        emit Model2Entry(msg.sender, false, evidenceId, amount, netAmount,
            amount - netAmount, a.grossPositionBasis);
    }

    /** Only caller-owned matured NET principal, within the shared rolling-24h ceiling. */
    function withdrawPrincipal(uint256 amount) external nonReentrant {
        Account storage a = _accounts[msg.sender];
        if (amount == 0) revert InvalidAmount();
        if (a.principal < amount) revert InsufficientPrincipal();
        _consumeWithdrawalCap(msg.sender, amount);
        uint256 grossConsumed = _consumeMaturedPrincipal(msg.sender, amount);
        a.principal -= amount;
        a.grossPositionBasis -= grossConsumed;
        totalPrincipal -= amount;
        _updateTeamVolume(msg.sender, grossConsumed, false);
        if (a.grossPositionBasis < MIN_ACTIVE_DIRECT && a.countedInParent) {
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
     * tranche. The disclosed 20% company allocation is transferred to the
     * splitter and the remaining 80% is credited as net principal.
     * This does not increase externalDepositBasis or the withdrawal allowance.
     */
    function reinvestRewards(uint256 amount) external whenNotPaused nonReentrant {
        Account storage a = _accounts[msg.sender];
        if (!a.everDeposited || amount == 0 || amount > a.baseRewards + a.referralRewards)
            revert InvalidAmount();
        if (a.grossPositionBasis + amount > MAX_PERSONAL_CAPITAL) revert ExceedsCapitalLimit();
        uint256 fromBase = a.baseRewards < amount ? a.baseRewards : amount;
        a.baseRewards -= fromBase;
        a.referralRewards -= amount - fromBase;
        totalClaimableRewards -= amount;
        if (a.countedInParent) {
            a.countedInParent = false;
            --_accounts[a.referrer].activeDirects;
            emit DirectSynced(msg.sender, a.referrer, false);
        }
        uint256 netAmount = amount - amount / 5;
        a.principal += netAmount;
        a.grossPositionBasis += amount;
        totalPrincipal += netAmount;
        a.lastDepositAt = block.timestamp;
        uint64 unlockAt = uint64(block.timestamp + WITHDRAWAL_LOCK);
        _principalTranches[msg.sender].push(PrincipalTranche(netAmount, unlockAt, amount));
        _updateTeamVolume(msg.sender, amount, true);
        bytes32 evidenceId = _allocateCompanyShare(amount, true);
        emit Reinvested(msg.sender, amount, unlockAt);
        emit Model2Entry(msg.sender, true, evidenceId, amount, netAmount,
            amount - netAmount, a.grossPositionBasis);
    }

    /** Total actually paid in (now - 24h, now], including principal AND reward claims. */
    function withdrawnInLast24Hours(address user) public view returns (uint256) {
        WithdrawalCheckpoint[] storage points = _withdrawalCheckpoints[user];
        uint256 n = points.length;
        if (n == 0) return 0;
        uint256 cumulative = points[n - 1].cumulativeGross;
        if (block.timestamp < WITHDRAWAL_WINDOW) return cumulative;
        uint256 cutoff = block.timestamp - WITHDRAWAL_WINDOW;
        uint256 low;
        uint256 high = n;
        // Upper bound: first checkpoint whose timestamp is later than cutoff.
        while (low < high) {
            uint256 middle = low + (high - low) / 2;
            if (points[middle].timestamp <= cutoff) low = middle + 1;
            else high = middle;
        }
        uint256 expiredCumulative = low == 0 ? 0 : points[low - 1].cumulativeGross;
        return cumulative - expiredCumulative;
    }

    function remainingWithdrawalCap(address user) public view returns (uint256) {
        uint256 limit = externalDepositBasis[user] / 5;
        uint256 spent = withdrawnInLast24Hours(user);
        return spent >= limit ? 0 : limit - spent;
    }

    /** Retains old read ABI, now returning the LIVE rolling-window start and amount. */
    function withdrawalWindows(address user) external view returns (uint64 startedAt, uint256 spentGross) {
        startedAt = uint64(block.timestamp >= WITHDRAWAL_WINDOW ? block.timestamp - WITHDRAWAL_WINDOW : 0);
        spentGross = withdrawnInLast24Hours(user);
    }

    function withdrawalCheckpointCount(address user) external view returns (uint256) {
        return _withdrawalCheckpoints[user].length;
    }
    function principalTrancheCount(address user) external view returns (uint256) {
        return _principalTranches[user].length;
    }
    function principalTrancheAt(address user, uint256 i) external view returns (uint256 remaining, uint64 unlockAt) {
        PrincipalTranche storage t = _principalTranches[user][i];
        return (t.remaining, t.unlockAt);
    }
    function principalTrancheGrossAt(address user, uint256 i) external view returns (uint256 grossRemaining) {
        return _principalTranches[user][i].grossRemaining;
    }
    function previewEntry(uint256 grossAmount) external pure returns (uint256 netPrincipal, uint256 companyAllocation) {
        companyAllocation = grossAmount / 5;
        netPrincipal = grossAmount - companyAllocation;
    }

    function _allocateCompanyShare(uint256 grossAmount, bool reinvest) private returns (bytes32 evidenceId) {
        uint256 allocation = grossAmount / 5;
        if (allocation == 0) return bytes32(0);
        evidenceId = keccak256(abi.encode("NEXORA_MODEL2_ENTRY", block.chainid, address(this),
            msg.sender, ++distributionNonce, grossAmount, reinvest));
        asset.forceApprove(address(companySplitter), allocation);
        companySplitter.fundDistribution(allocation, evidenceId);
        asset.forceApprove(address(companySplitter), 0);
    }

    function _consumeWithdrawalCap(address user, uint256 amount) private {
        if (amount > remainingWithdrawalCap(user)) revert WithdrawalLimitExceeded();
        WithdrawalCheckpoint[] storage points = _withdrawalCheckpoints[user];
        uint256 n = points.length;
        uint256 cumulative = (n == 0 ? 0 : points[n - 1].cumulativeGross) + amount;
        if (n != 0 && points[n - 1].timestamp == block.timestamp) {
            points[n - 1].cumulativeGross = cumulative;
        } else {
            points.push(WithdrawalCheckpoint(uint64(block.timestamp), cumulative));
        }
        emit WithdrawalWindowUsed(user, amount,
            block.timestamp >= WITHDRAWAL_WINDOW ? block.timestamp - WITHDRAWAL_WINDOW : 0);
    }

    function _consumeMaturedPrincipal(address user, uint256 amount) private returns (uint256 grossConsumed) {
        PrincipalTranche[] storage list = _principalTranches[user];
        uint256 i = _nextTranche[user];
        uint256 needed = amount;
        while (needed != 0 && i < list.length) {
            PrincipalTranche storage t = list[i];
            if (block.timestamp < t.unlockAt) break;
            uint256 usedNet = t.remaining < needed ? t.remaining : needed;
            uint256 usedGross = usedNet == t.remaining ? t.grossRemaining :
                Math.mulDiv(t.grossRemaining, usedNet, t.remaining, Math.Rounding.Ceil);
            t.remaining -= usedNet;
            t.grossRemaining -= usedGross;
            grossConsumed += usedGross;
            needed -= usedNet;
            if (t.remaining != 0) break;
            ++i;
        }
        if (needed != 0) revert NoMaturedTranche();
        _nextTranche[user] = i;
    }

    /** Permissionless, but guarded against callbacks during deposit/reinvest transitions. */
    function syncDirect(address member) external nonReentrant {
        Account storage a = _accounts[member];
        if (a.referrer == address(0) || a.grossPositionBasis < MIN_ACTIVE_DIRECT) revert NotEligible();
        if (block.timestamp < a.lastDepositAt + MATURITY) revert NotMature();
        if (a.countedInParent) revert AlreadyQualified();
        a.countedInParent = true;
        ++_accounts[a.referrer].activeDirects;
        emit DirectSynced(member, a.referrer, true);
    }

    /** Real funding from outside the user-principal ledger; source of profits is not proven here. */
    function fundRewards(uint256 amount) external onlyRole(FUNDER_ROLE) nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) - beforeBalance != amount) revert FeeOnTransferNotSupported();
        unallocatedRewards += amount;
        emit RewardPoolFunded(msg.sender, amount);
    }

    /** Funded, authorized allocation, not an automatic or guaranteed yield. */
    function allocateReward(address member, uint256 amount, bytes32 reportId)
        external onlyRole(ALLOCATOR_ROLE) whenNotPaused nonReentrant
    {
        if (member == address(0) || amount == 0) revert InvalidAmount();
        if (reportId == bytes32(0) || usedReportIds[reportId]) revert InvalidOrUsedReport();
        Account storage a = _accounts[member];
        uint16 rate = tierBps(member);
        if (rate == 0) revert NotEligible();
        if (a.lastCreditAt != 0 && block.timestamp < a.lastCreditAt + MATURITY) revert CreditTooSoon();
        if (amount > a.grossPositionBasis * rate / BPS) revert ExceedsDailyCap();
        address[3] memory earners;
        uint256[3] memory bonuses;
        uint256 cost = amount;
        address ancestor = a.referrer;
        for (uint8 level; level < 3 && ancestor != address(0); ++level) {
            if (_qualifiedReferrer(ancestor)) {
                uint256 bps = level == 0 ? 1500 : (level == 1 ? 700 : 300);
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
        for (uint8 level; level < 3; ++level) {
            if (bonuses[level] == 0) continue;
            _accounts[earners[level]].referralRewards += bonuses[level];
            emit ReferralReward(earners[level], member, level + 1, bonuses[level]);
        }
        emit RewardAllocated(member, reportId, amount, cost - amount, rate);
    }

    /** Backed rewards mature 90 days after first deposit; principal and claims SHARE the rolling cap. */
    function claimRewards() external nonReentrant returns (uint256 amount) {
        Account storage a = _accounts[msg.sender];
        if (!a.everDeposited || block.timestamp < a.firstDepositAt + WITHDRAWAL_LOCK) revert NotMature();
        uint256 available = a.baseRewards + a.referralRewards;
        if (available == 0) revert InvalidAmount();
        uint256 limit = remainingWithdrawalCap(msg.sender);
        if (limit == 0) revert WithdrawalLimitExceeded();
        amount = available < limit ? available : limit;
        _consumeWithdrawalCap(msg.sender, amount);
        uint256 fromBase = a.baseRewards < amount ? a.baseRewards : amount;
        a.baseRewards -= fromBase;
        a.referralRewards -= amount - fromBase;
        totalClaimableRewards -= amount;
        asset.safeTransfer(msg.sender, amount);
        emit WithdrawalPolicy(msg.sender, amount, 0);
        emit RewardClaimed(msg.sender, amount);
    }

    function tierBps(address member) public view returns (uint16) {
        Account storage a = _accounts[member];
        if (a.grossPositionBasis < MIN_DEPOSIT || a.lastDepositAt == 0 || block.timestamp < a.lastDepositAt + MATURITY)
            return 0;
        if (a.activeDirects < 2 || teamVolume[member] < 2500 * UNIT) return 100;
        if (!_hasBalancedBranches(member)) return 100;
        uint256 c = a.grossPositionBasis;
        uint256 d = a.activeDirects;
        uint256 v = teamVolume[member];
        if (c >= 25000 * UNIT && d >= 10 && v >= 125000 * UNIT) return 250;
        if (c >= 10000 * UNIT && d >= 6 && v >= 50000 * UNIT) return 200;
        if (c >= 2500 * UNIT && d >= 4 && v >= 12500 * UNIT) return 150;
        if (c >= 500 * UNIT && d >= 2 && v >= 2500 * UNIT) return 125;
        return 100;
    }
    function _qualifiedReferrer(address who) internal view returns (bool) {
        Account storage a = _accounts[who];
        return a.grossPositionBasis >= MIN_ACTIVE_DIRECT && a.lastDepositAt != 0 && block.timestamp >= a.lastDepositAt + MATURITY;
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
            if (increase) { teamVolume[parent] += amount; branchVolume[parent][branch] += amount; }
            else { teamVolume[parent] -= amount; branchVolume[parent][branch] -= amount; }
            branch = parent;
            parent = _accounts[parent].referrer;
        }
    }
    function directCount(address user) external view returns (uint256) { return _children[user].length; }
    function directAt(address user, uint256 index) external view returns (address) { return _children[user][index]; }
    function getAccount(address user) external view returns (Account memory) { return _accounts[user]; }

    /** Gross receipt and plan basis are not backed liabilities; netPrincipal is actual capital. */
    function accountSnapshot(address user) external view returns (
        uint256 grossDepositedLifetime, uint256 grossOpenPlanBasis, uint256 netPrincipal,
        uint256 claimableRewards, uint256 availableDailyWithdrawalCap
    ) {
        Account storage a = _accounts[user];
        return (a.grossDepositsLifetime, a.grossPositionBasis, a.principal,
            a.baseRewards + a.referralRewards, remainingWithdrawalCap(user));
    }
    function isSolvent() external view returns (bool) {
        return asset.balanceOf(address(this)) >= totalPrincipal + unallocatedRewards + totalClaimableRewards;
    }
    // Pausing prevents new risk, not already-matured exits.
    function pause() external onlyRole(GUARDIAN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
