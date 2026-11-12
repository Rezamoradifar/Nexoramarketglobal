// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraRevenueRouter
 * @notice TESTNET PROTOTYPE (NOT AUDITED OR DEPLOYED).
 *
 * Routes only newly transferred, independently funded business revenue:
 *   80% -> NexoraProfitVault unallocated user-reward reserve.
 *   20% -> NexoraRevenueSplitter for owner + ten beneficiary wallets.
 *
 * IMPORTANT: Never route user principal through this module. A user deposit
 * goes directly to NexoraProfitVault.deposit and remains 100% withdrawable.
 *
 * This contract does NOT prove that funded amounts represent realized profit,
 * does not generate trading income, and does not promise daily returns.
 */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {NexoraProfitVault} from "./NexoraProfitVault.sol";
import {NexoraRevenueSplitter} from "./NexoraRevenueSplitter.sol";

contract NexoraRevenueRouter is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant VAULT_BPS = 8_000;
    uint256 public constant WALLETS_BPS = 2_000;

    bytes32 public constant REVENUE_FUNDER_ROLE = keccak256("REVENUE_FUNDER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    IERC20 public immutable asset;
    NexoraProfitVault public immutable vault;
    NexoraRevenueSplitter public immutable splitter;

    mapping(bytes32 => bool) public usedEvidenceIds;
    uint256 public totalRevenueFunded;
    uint256 public totalVaultReservesFunded;
    uint256 public totalWalletPoolFunded;

    event RevenueRouted(
        address indexed funder,
        bytes32 indexed evidenceId,
        uint256 grossRevenue,
        uint256 vaultReserve,
        uint256 recipientPool
    );

    error ZeroAddress();
    error InvalidDestination();
    error InvalidAmount();
    error InvalidOrUsedEvidenceId();
    error FeeOnTransferNotSupported();

    constructor(
        address token_,
        address vault_,
        address splitter_,
        address admin_,
        address revenueFunder_
    ) {
        if (token_ == address(0) || vault_ == address(0) ||
            splitter_ == address(0) || admin_ == address(0) ||
            revenueFunder_ == address(0)) revert ZeroAddress();

        if (vault_ == splitter_ || vault_.code.length == 0 || splitter_.code.length == 0) {
            revert InvalidDestination();
        }
        if (
            address(NexoraProfitVault(vault_).asset()) != token_ ||
            address(NexoraRevenueSplitter(splitter_).asset()) != token_
        ) revert InvalidDestination();

        asset = IERC20(token_);
        vault = NexoraProfitVault(vault_);
        splitter = NexoraRevenueSplitter(splitter_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(GUARDIAN_ROLE, admin_);
        _grantRole(REVENUE_FUNDER_ROLE, revenueFunder_);
    }

    function previewSplit(uint256 amount)
        public pure returns (uint256 vaultReserve, uint256 recipientPool)
    {
        recipientPool = amount * WALLETS_BPS / BPS;
        vaultReserve = amount - recipientPool;
    }

    /**
     * @notice Atomic revenue routing. Funder must own or control the revenue,
     * and must approve this router for exactly the requested amount.
     * @dev Configure FUNDER_ROLE on BOTH destination contracts for this router
     * before funding. An error at either destination reverts the entire action.
     * No owner/admin withdrawal function exists on the router.
     */
    function fundAndRoute(uint256 amount, bytes32 evidenceId)
        external onlyRole(REVENUE_FUNDER_ROLE) whenNotPaused nonReentrant
    {
        if (amount == 0) revert InvalidAmount();
        if (evidenceId == bytes32(0) || usedEvidenceIds[evidenceId]) {
            revert InvalidOrUsedEvidenceId();
        }
        (uint256 vaultPart, uint256 walletPart) = previewSplit(amount);
        if (vaultPart == 0 || walletPart == 0) revert InvalidAmount();

        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) - beforeBalance != amount) {
            revert FeeOnTransferNotSupported();
        }

        // Checked before cross-contract calls; any downstream failure reverts it.
        usedEvidenceIds[evidenceId] = true;

        // Explicitly account 80% inside the reward-reserve vault.
        asset.forceApprove(address(vault), vaultPart);
        vault.fundRewards(vaultPart);
        asset.forceApprove(address(vault), 0);

        // Only 20% enters the 11-wallet splitter; its own configured BPS
        // determine how this 20% is shared among owner and ten wallets.
        asset.forceApprove(address(splitter), walletPart);
        splitter.fundDistribution(walletPart, evidenceId);
        asset.forceApprove(address(splitter), 0);

        totalRevenueFunded += amount;
        totalVaultReservesFunded += vaultPart;
        totalWalletPoolFunded += walletPart;

        emit RevenueRouted(msg.sender, evidenceId, amount, vaultPart, walletPart);
    }

    function pause() external onlyRole(GUARDIAN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}
