// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraModel2MainnetVault} from "./NexoraModel2MainnetVault.sol";
import {NexoraRevenueSplitter} from "./NexoraRevenueSplitter.sol";

/**
 * @notice UN-AUDITED production candidate. Local review only; not a launch.
 * Creates the vault and the eleven-recipient splitter atomically for chain 56
 * and fixed Binance-Peg USDT. Role control, the funding source, beneficiary
 * ownership, and final bytecode require separate verification before use.
 */
contract NexoraModel2MainnetFactory {
    uint256 public constant MAINNET_CHAIN_ID = 56;
    address public constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;

    NexoraModel2MainnetVault public immutable vault;
    NexoraRevenueSplitter public immutable splitter;
    address public immutable governanceAdmin;
    address public immutable rewardFunder;
    address public immutable rewardAllocator;

    error MainnetOnly(uint256 actualChainId);
    error ZeroRole();
    error InaccessibleRole();
    error InaccessibleBeneficiary();

    event MainnetSystemCreated(address indexed vault, address indexed splitter,
        address token, address governanceAdmin, address rewardFunder, address rewardAllocator);

    constructor(address admin, address funder, address allocator, address[11] memory wallets) {
        if (block.chainid != MAINNET_CHAIN_ID) revert MainnetOnly(block.chainid);
        if (admin == address(0) || funder == address(0) || allocator == address(0)) revert ZeroRole();

        NexoraRevenueSplitter s = new NexoraRevenueSplitter(BSC_USDT, address(this), address(this), wallets);
        NexoraModel2MainnetVault v = new NexoraModel2MainnetVault(address(this), funder, allocator, address(s));

        // None of these contracts can act as an operator or claim its own
        // beneficiary allocation. Reject unrecoverable bootstrap settings.
        if (admin == address(this) || admin == address(s) || admin == address(v) ||
            funder == address(this) || funder == address(s) || funder == address(v) ||
            allocator == address(this) || allocator == address(s) || allocator == address(v)) revert InaccessibleRole();
        for (uint256 i; i < wallets.length; ++i) {
            if (wallets[i] == address(this) || wallets[i] == address(s) || wallets[i] == address(v))
                revert InaccessibleBeneficiary();
        }

        s.grantRole(s.FUNDER_ROLE(), address(v));
        s.grantRole(s.DEFAULT_ADMIN_ROLE(), admin);
        s.grantRole(s.GUARDIAN_ROLE(), admin);
        v.grantRole(v.DEFAULT_ADMIN_ROLE(), admin);
        v.grantRole(v.GUARDIAN_ROLE(), admin);
        s.revokeRole(s.FUNDER_ROLE(), address(this));
        s.revokeRole(s.GUARDIAN_ROLE(), address(this));
        v.revokeRole(v.GUARDIAN_ROLE(), address(this));
        s.renounceRole(s.DEFAULT_ADMIN_ROLE(), address(this));
        v.renounceRole(v.DEFAULT_ADMIN_ROLE(), address(this));

        vault = v;
        splitter = s;
        governanceAdmin = admin;
        rewardFunder = funder;
        rewardAllocator = allocator;
        emit MainnetSystemCreated(address(v), address(s), BSC_USDT, admin, funder, allocator);
    }
}
