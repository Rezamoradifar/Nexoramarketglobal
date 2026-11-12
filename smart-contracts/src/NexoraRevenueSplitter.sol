// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraRevenueSplitter
 * @notice Un-audited TESTNET prototype for one owner wallet + ten other wallets.
 * @dev Accepts only separately funded ERC20 distributions, NEVER user principal.
 *
 * Payout percentages are FIXED BY CODE (only addresses are constructor inputs):
 * - payoutWallets[0] gets 50% of this splitter's 20% revenue pool
 *   = 10% of gross routed revenue.
 * - payoutWallets[1..10] each gets 5% of the 20% pool
 *   = 1% of gross routed revenue each.
 * - Together these recipients receive only the router's 20% pool.
 *
 * This contract cannot verify that deposited distribution tokens represent
 * realized *net profit*. Real business accounting/audit is off-chain.
 * It is deliberately NOT wired to NexoraProfitVault or user deposits.
 */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NexoraRevenueSplitter is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant RECIPIENT_COUNT = 11;
    uint256 public constant BPS = 10_000;
    uint16 public constant OWNER_POOL_BPS = 5_000;
    uint16 public constant PARTNER_POOL_BPS = 500;
    bytes32 public constant FUNDER_ROLE = keccak256("FUNDER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    IERC20 public immutable asset;

    address[11] public payoutWallets;
    uint16[11] public sharesBps;

    mapping(address => uint256) public claimable;
    mapping(bytes32 => bool) public usedEvidenceIds;

    uint256 public totalFunded;
    uint256 public totalClaimed;
    uint256 public totalClaimable;

    event RevenueDistributionFunded(
        address indexed funder,
        bytes32 indexed evidenceId,
        uint256 amount
    );
    event ShareAllocated(
        address indexed recipient,
        uint8 indexed index,
        uint256 amount,
        uint16 shareBps
    );
    event ShareClaimed(address indexed recipient, uint256 amount);

    error ZeroAddress();
    error InvalidAsset();
    error DuplicateWallet();
    error InvalidAmount();
    error DuplicateOrMissingEvidence();
    error FeeOnTransferNotSupported();
    error NothingToClaim();

    constructor(
        address token_,
        address admin_,
        address funder_,
        address[11] memory wallets_
    ) {
        if (token_ == address(0) || admin_ == address(0) || funder_ == address(0)) {
            revert ZeroAddress();
        }
        if (token_.code.length == 0 || IERC20Metadata(token_).decimals() != 18) {
            revert InvalidAsset();
        }

        for (uint256 i; i < RECIPIENT_COUNT; ++i) {
            if (wallets_[i] == address(0)) revert ZeroAddress();
            for (uint256 j; j < i; ++j) {
                if (wallets_[i] == wallets_[j]) revert DuplicateWallet();
            }
            payoutWallets[i] = wallets_[i];
            sharesBps[i] = i == 0 ? OWNER_POOL_BPS : PARTNER_POOL_BPS;
        }

        asset = IERC20(token_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(GUARDIAN_ROLE, admin_);
        _grantRole(FUNDER_ROLE, funder_);
    }

    /**
     * @notice Explicitly fund a new distribution. The funder's 11 payouts
     * are fully backed by newly transferred stablecoins.
     * @dev Authorized funding does not prove net profit, hence evidenceId
     * must identify independently reviewable accounting documentation.
     */
    function fundDistribution(uint256 amount, bytes32 evidenceId)
        external
        onlyRole(FUNDER_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) revert InvalidAmount();
        if (evidenceId == bytes32(0) || usedEvidenceIds[evidenceId]) {
            revert DuplicateOrMissingEvidence();
        }

        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) - beforeBalance != amount) {
            revert FeeOnTransferNotSupported();
        }

        usedEvidenceIds[evidenceId] = true;
        totalFunded += amount;
        totalClaimable += amount;

        // Give rounding remainder to owner index 0; no rounding dust trapped.
        uint256 othersTotal;
        for (uint8 i = 1; i < RECIPIENT_COUNT; ++i) {
            uint256 share = amount * sharesBps[i] / BPS;
            claimable[payoutWallets[i]] += share;
            othersTotal += share;
            emit ShareAllocated(payoutWallets[i], i, share, sharesBps[i]);
        }
        uint256 ownerShare = amount - othersTotal;
        claimable[payoutWallets[0]] += ownerShare;
        emit ShareAllocated(payoutWallets[0], 0, ownerShare, sharesBps[0]);
        emit RevenueDistributionFunded(msg.sender, evidenceId, amount);
    }

    /**
     * @notice Only each beneficiary can withdraw its share. Works when paused.
     * @dev Admin has no emergency sweep function and cannot confiscate funds.
     */
    function claim() external nonReentrant returns (uint256 amount) {
        amount = claimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        claimable[msg.sender] = 0;
        totalClaimable -= amount;
        totalClaimed += amount;
        asset.safeTransfer(msg.sender, amount);
        emit ShareClaimed(msg.sender, amount);
    }

    function getConfiguration()
        external view
        returns (address[11] memory wallets, uint16[11] memory bps)
    {
        return (payoutWallets, sharesBps);
    }

    function isSolvent() external view returns (bool) {
        return asset.balanceOf(address(this)) >= totalClaimable;
    }

    function pause() external onlyRole(GUARDIAN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
