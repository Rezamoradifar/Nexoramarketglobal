// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraSystemFactory
 * @notice Deployment coordination ONLY. NOT AUDITED. Do not use with mainnet funds.
 *
 * Deploys the three Nexora contracts and performs atomic role bootstrap.
 * No ERC20 tokens are handled here; no deposit or earning is created.
 *
 * Production prerequisites remain an independent audit, legal clearance,
 * verifiable revenue policy, BNB testnet dress rehearsal, and 11 real
 * beneficiary public addresses.
 */
import {NexoraProfitVault} from "./NexoraProfitVault.sol";
import {NexoraRevenueSplitter} from "./NexoraRevenueSplitter.sol";
import {NexoraRevenueRouter} from "./NexoraRevenueRouter.sol";

contract NexoraSystemFactory {
    // Binance-Peg BSC-USD / Binance-Peg USDT is NOT Tether-native USDT.
    // Independently verify this address and its 18 decimals before any release.
    address public constant MAINNET_BINANCE_PEG_USDT =
        0x55d398326f99059fF775485246999027B3197955;

    uint256 public constant BSC_MAINNET_CHAIN_ID = 56;
    uint256 public constant BSC_TESTNET_CHAIN_ID = 97;

    NexoraProfitVault public immutable vault;
    NexoraRevenueSplitter public immutable splitter;
    NexoraRevenueRouter public immutable router;

    address public immutable governanceAdmin;
    address public immutable revenueFunder;
    address public immutable rewardAllocator;

    event NexoraSystemCreated(
        uint256 indexed chainId,
        address indexed vault,
        address indexed splitter,
        address router,
        address token,
        address governanceAdmin
    );

    error UnsupportedChain(uint256 chainId);
    error IncorrectMainnetToken();
    error MainnetRequiresContractAdmin();
    error InvalidRoleAddress();
    error RoleSeparationRequired();

    constructor(
        address token_,
        address adminMultisig_,
        address externalRevenueFunder_,
        address externalRewardAllocator_,
        address[11] memory payoutWallets_
    ) {
        if (block.chainid != BSC_MAINNET_CHAIN_ID &&
            block.chainid != BSC_TESTNET_CHAIN_ID) {
            revert UnsupportedChain(block.chainid);
        }
        if (token_ == address(0) || adminMultisig_ == address(0) ||
            externalRevenueFunder_ == address(0) ||
            externalRewardAllocator_ == address(0)) revert InvalidRoleAddress();

        // Operational independence: avoid reusing one key for governance,
        // reward allocation and independently sourced revenue funding.
        if (adminMultisig_ == externalRevenueFunder_ ||
            adminMultisig_ == externalRewardAllocator_ ||
            externalRewardAllocator_ == externalRevenueFunder_) {
            revert RoleSeparationRequired();
        }

        if (block.chainid == BSC_MAINNET_CHAIN_ID) {
            if (token_ != MAINNET_BINANCE_PEG_USDT) {
                revert IncorrectMainnetToken();
            }
            if (adminMultisig_.code.length == 0) {
                revert MainnetRequiresContractAdmin();
            }
        }

        governanceAdmin = adminMultisig_;
        revenueFunder = externalRevenueFunder_;
        rewardAllocator = externalRewardAllocator_;

        // The factory temporarily acts as admin only during construction.
        NexoraProfitVault v = new NexoraProfitVault(
            token_, address(this), address(this), externalRewardAllocator_
        );
        NexoraRevenueSplitter s = new NexoraRevenueSplitter(
            token_, address(this), address(this), payoutWallets_
        );
        NexoraRevenueRouter r = new NexoraRevenueRouter(
            token_, address(v), address(s), adminMultisig_, externalRevenueFunder_
        );

        // Configure the only routine funding path: 80% vault, 20% splitter.
        v.grantRole(v.FUNDER_ROLE(), address(r));
        s.grantRole(s.FUNDER_ROLE(), address(r));

        // Move administration and pause control to governance.
        v.grantRole(v.DEFAULT_ADMIN_ROLE(), adminMultisig_);
        s.grantRole(s.DEFAULT_ADMIN_ROLE(), adminMultisig_);
        v.grantRole(v.GUARDIAN_ROLE(), adminMultisig_);
        s.grantRole(s.GUARDIAN_ROLE(), adminMultisig_);

        // No factory residual funding/guardian/admin authority.
        v.revokeRole(v.FUNDER_ROLE(), address(this));
        s.revokeRole(s.FUNDER_ROLE(), address(this));
        v.revokeRole(v.GUARDIAN_ROLE(), address(this));
        s.revokeRole(s.GUARDIAN_ROLE(), address(this));
        v.renounceRole(v.DEFAULT_ADMIN_ROLE(), address(this));
        s.renounceRole(s.DEFAULT_ADMIN_ROLE(), address(this));

        vault = v;
        splitter = s;
        router = r;

        emit NexoraSystemCreated(
            block.chainid, address(v), address(s), address(r), token_, adminMultisig_
        );
    }
}
