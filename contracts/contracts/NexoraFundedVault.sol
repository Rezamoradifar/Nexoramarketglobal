// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraFundedVault
 * @notice TESTNET PROTOTYPE. No guaranteed yield, no trading and no automated
 * daily earnings. All profits and referral credits require a corresponding
 * new ERC20 transfer from an operator account.
 *
 * DO NOT USE WITH REAL FUNDS BEFORE AN INDEPENDENT AUDIT.
 */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NexoraFundedVault is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    uint256 public immutable minInitialDeposit;
    uint256 public immutable maxPrincipalPerWallet;

    address public settlementOperator;

    uint256 public totalPrincipal;
    uint256 public totalCredits;

    mapping(address => bool) public registered;
    mapping(address => address) public sponsor;
    mapping(address => uint256) public principalOf;
    mapping(address => uint256) public availableCredit;
    mapping(address => uint256) public totalFundedUserProfit;
    mapping(address => uint256) public totalFundedReferralCredit;

    uint256[3] public referralBps = [uint256(1500), 700, 300];
    uint256 private constant BPS = 10_000;

    event Registered(address indexed member, address indexed sponsor);
    event Deposited(address indexed member, uint256 amount);
    event PrincipalWithdrawn(address indexed member, uint256 amount);
    event ProfitFunded(address indexed member, address indexed operator, uint256 profit, uint256 totalTransferred);
    event ReferralCredited(address indexed member, address indexed ancestor, uint8 level, uint256 amount);
    event CreditWithdrawn(address indexed member, uint256 amount);
    event OperatorChanged(address indexed previousOperator, address indexed newOperator);

    error NotOperator();
    error InvalidAddress();
    error InvalidAmount();
    error UnregisteredSponsor();
    error AlreadyRegistered();
    error CannotSponsorSelf();
    error BalanceMismatch();
    error Insolvent();

    modifier onlySettlementOperator() {
        if (msg.sender != settlementOperator) revert NotOperator();
        _;
    }

    constructor(address token, address initialAdmin, address initialOperator)
        Ownable(initialAdmin)
    {
        if (token == address(0) || initialAdmin == address(0) || initialOperator == address(0))
            revert InvalidAddress();
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals == 6 || decimals == 18, "Supported decimals: 6 or 18");
        asset = IERC20(token);
        minInitialDeposit = 10 * 10 ** uint256(decimals);
        maxPrincipalPerWallet = 50_000 * 10 ** uint256(decimals);
        settlementOperator = initialOperator;
        registered[initialAdmin] = true; // Optional root for referrals.
    }

    /// @notice Sponsor is permanent; a member may register without a sponsor.
    function register(address referrer) external whenNotPaused {
        _register(msg.sender, referrer);
    }

    function _register(address member, address referrer) internal {
        if (registered[member]) revert AlreadyRegistered();
        if (referrer == member) revert CannotSponsorSelf();
        if (referrer != address(0) && !registered[referrer])
            revert UnregisteredSponsor();
        registered[member] = true;
        sponsor[member] = referrer;
        emit Registered(member, referrer);
    }

    /// @notice Deposits stay in this vault. There is no external trading manager.
    function deposit(uint256 amount, address referrer) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (!registered[msg.sender]) {
            if (amount < minInitialDeposit) revert InvalidAmount();
            _register(msg.sender, referrer);
        } else if (referrer != address(0) && referrer != sponsor[msg.sender]) {
            revert InvalidAddress();
        }

        if (principalOf[msg.sender] + amount > maxPrincipalPerWallet)
            revert InvalidAmount();

        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) - beforeBalance != amount)
            revert BalanceMismatch();

        principalOf[msg.sender] += amount;
        totalPrincipal += amount;
        _checkSolvency();
        emit Deposited(msg.sender, amount);
    }

    /// @notice Principal withdrawals are intentionally available even during a pause.
    function withdrawPrincipal(uint256 amount) external nonReentrant {
        if (amount == 0 || amount > principalOf[msg.sender]) revert InvalidAmount();
        principalOf[msg.sender] -= amount;
        totalPrincipal -= amount;
        asset.safeTransfer(msg.sender, amount);
        _checkSolvency();
        emit PrincipalWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Credits user and their up to three registered ancestors,
     * requiring exact NEW ERC20 funding for every credited unit.
     * Operator cannot draw principal or assign unfunded "paper profit".
     *
     * @dev Not evidence of actual trading profits: an independent trade ledger,
     * auditor and legal review are needed before any production rollout.
     */
    function settleFundedProfit(address member, uint256 userProfit)
        external
        onlySettlementOperator
        nonReentrant
        whenNotPaused
    {
        if (!registered[member] || principalOf[member] == 0 || userProfit == 0)
            revert InvalidAmount();

        uint256[3] memory referralAmounts;
        address[3] memory ancestors;
        uint256 extra;

        address ancestor = sponsor[member];
        for (uint8 i = 0; i < 3 && ancestor != address(0); i++) {
            referralAmounts[i] = userProfit * referralBps[i] / BPS;
            ancestors[i] = ancestor;
            extra += referralAmounts[i];
            ancestor = sponsor[ancestor];
        }

        uint256 fundingRequired = userProfit + extra;
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), fundingRequired);
        if (asset.balanceOf(address(this)) - beforeBalance != fundingRequired)
            revert BalanceMismatch();

        availableCredit[member] += userProfit;
        totalFundedUserProfit[member] += userProfit;
        totalCredits += fundingRequired;

        for (uint8 j = 0; j < 3; j++) {
            if (ancestors[j] != address(0)) {
                availableCredit[ancestors[j]] += referralAmounts[j];
                totalFundedReferralCredit[ancestors[j]] += referralAmounts[j];
                emit ReferralCredited(member, ancestors[j], j + 1, referralAmounts[j]);
            }
        }
        _checkSolvency();
        emit ProfitFunded(member, msg.sender, userProfit, fundingRequired);
    }

    /// @notice Withdraw funded profit/referral credit; allowed during pause.
    function withdrawCredit(uint256 amount) external nonReentrant {
        if (amount == 0 || amount > availableCredit[msg.sender])
            revert InvalidAmount();
        availableCredit[msg.sender] -= amount;
        totalCredits -= amount;
        asset.safeTransfer(msg.sender, amount);
        _checkSolvency();
        emit CreditWithdrawn(msg.sender, amount);
    }

    function setSettlementOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert InvalidAddress();
        emit OperatorChanged(settlementOperator, newOperator);
        settlementOperator = newOperator;
    }

    /// @dev Does NOT block principal or funded-credit withdrawals.
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function solvent() public view returns (bool) {
        return asset.balanceOf(address(this)) >= totalPrincipal + totalCredits;
    }
    function surplus() external view returns (uint256) {
        uint256 balance = asset.balanceOf(address(this));
        uint256 liabilities = totalPrincipal + totalCredits;
        return balance > liabilities ? balance - liabilities : 0;
    }
    function _checkSolvency() internal view {
        if (!solvent()) revert Insolvent();
    }
}
