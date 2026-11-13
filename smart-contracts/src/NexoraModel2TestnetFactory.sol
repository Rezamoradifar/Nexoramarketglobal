// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraModel2TestnetFactory
 * @notice BNB CHAIN TESTNET ONLY (chain ID 97), not production.
 *
 * Atomically deploys:
 *  1. NexoraRevenueSplitter: 30/100 of 20% to owner, 7/100 to each
 *     of ten corporate recipients. All recipients must be real beneficiaries.
 *  2. NexoraModel2Vault: 80% NET backed user principal and transparent
 *     100% GROSS deposit/plan reference; funded reward pool separately.
 *
 * The owner/company distributions are triggered ONLY by actual user deposits
 * or voluntary funded reward reinvests. Independently funded reward revenue
 * enters the vault as 100% reward reserves, not another distribution.
 *
 * No investor trading, guaranteed returns, or live market integrations.
 * No MAINNET use is possible through this factory; a separately audited
 * and authorized mainnet release is required.
 */
import {NexoraModel2Vault} from "./NexoraModel2Vault.sol";
import {NexoraRevenueSplitter} from "./NexoraRevenueSplitter.sol";

contract NexoraModel2TestnetFactory {
    uint256 public constant TESTNET_CHAIN_ID = 97;

    NexoraModel2Vault public immutable vault;
    NexoraRevenueSplitter public immutable splitter;
    address public immutable governanceAdmin;
    address public immutable revenueFunder;
    address public immutable rewardAllocator;

    error TestnetOnly(uint256 actualChainId);
    error ZeroRole();
    error RoleCollision();

    event TestnetSystemCreated(
        address indexed vault,
        address indexed splitter,
        address token,
        address governanceAdmin,
        address revenueFunder,
        address rewardAllocator
    );

    constructor(
        address token,
        address admin,
        address rewardsFunder,
        address allocator,
        address[11] memory payoutWallets
    ) {
        if (block.chainid != TESTNET_CHAIN_ID) revert TestnetOnly(block.chainid);
        if (token == address(0) || admin == address(0) ||
            rewardsFunder == address(0) || allocator == address(0)) {
            revert ZeroRole();
        }
        if (admin == rewardsFunder || admin == allocator ||
            rewardsFunder == allocator) revert RoleCollision();

        governanceAdmin = admin;
        revenueFunder = rewardsFunder;
        rewardAllocator = allocator;

        NexoraRevenueSplitter s = new NexoraRevenueSplitter(
            token, address(this), address(this), payoutWallets
        );
        NexoraModel2Vault v = new NexoraModel2Vault(
            token, address(this), rewardsFunder, allocator, address(s)
        );

        // User-initiated deposit / reinvest entries are the ONLY routine
        // company payout funding path; the splitter transfers from vault.
        s.grantRole(s.FUNDER_ROLE(), address(v));

        // Handoff admin and guardian to governance. Vault has no admin
        // sweep, no forced user withdrawal, and no trading API.
        s.grantRole(s.DEFAULT_ADMIN_ROLE(), admin);
        v.grantRole(v.DEFAULT_ADMIN_ROLE(), admin);
        s.grantRole(s.GUARDIAN_ROLE(), admin);
        v.grantRole(v.GUARDIAN_ROLE(), admin);

        s.revokeRole(s.FUNDER_ROLE(), address(this));
        s.revokeRole(s.GUARDIAN_ROLE(), address(this));
        v.revokeRole(v.GUARDIAN_ROLE(), address(this));
        s.renounceRole(s.DEFAULT_ADMIN_ROLE(), address(this));
        v.renounceRole(v.DEFAULT_ADMIN_ROLE(), address(this));

        vault = v;
        splitter = s;
        emit TestnetSystemCreated(
            address(v), address(s), token, admin, rewardsFunder, allocator
        );
    }
}
