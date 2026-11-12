// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraProfitVault} from "../src/NexoraProfitVault.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {NexoraRevenueRouter} from "../src/NexoraRevenueRouter.sol";
import {MockUSDT} from "./MockUSDT.sol";

interface VmRouter {
    function prank(address) external;
    function warp(uint256) external;
}

contract NexoraRevenueRouterTest {
    VmRouter private constant vm = VmRouter(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant U = 1e18;
    address private constant ALICE = address(0xA11CE);
    address private constant OUTSIDER = address(0xB0B);

    MockUSDT private token;
    NexoraProfitVault private vault;
    NexoraRevenueSplitter private splitter;
    NexoraRevenueRouter private router;
    address[11] private wallets;
    uint16[11] private shares;

    function setUp() public {
        vm.warp(100 days);
        token = new MockUSDT();
        vault = new NexoraProfitVault(address(token), address(this), address(this), address(this));
        // TEST-ONLY INTERNAL split of 20% wallet pool: owner 20%, ten wallets 8% each.
        // These are NOT the approved final wallet shares; user has only set 80/20 overall.
        wallets[0] = address(0x100);
        shares[0] = 2_000;
        for (uint256 i = 1; i < 11; ++i) {
            wallets[i] = address(uint160(0x100 + i));
            shares[i] = 800;
        }
        splitter = new NexoraRevenueSplitter(
            address(token), address(this), address(this), wallets, shares
        );
        router = new NexoraRevenueRouter(
            address(token), address(vault), address(splitter), address(this), address(this)
        );
        vault.grantRole(vault.FUNDER_ROLE(), address(router));
        splitter.grantRole(splitter.FUNDER_ROLE(), address(router));

        // Remove direct funding roles in test fixture so only routed revenue
        // can fund destinations without admin explicitly changing permission.
        vault.revokeRole(vault.FUNDER_ROLE(), address(this));
        splitter.revokeRole(splitter.FUNDER_ROLE(), address(this));

        token.mint(address(this), 1_000_000 * U);
        token.approve(address(router), type(uint256).max);
        token.mint(ALICE, 50_000 * U);
        vm.prank(ALICE);
        token.approve(address(vault), type(uint256).max);
    }

    function _eq(uint256 x, uint256 y) private pure {
        require(x == y, "Value mismatch");
    }

    function _expectRouterRevert(bytes memory callData) private {
        (bool ok,) = address(router).call(callData);
        require(!ok, "Expected revert");
    }

    function testEightyPercentIntoVaultAndTwentyPercentToElevenWallets() public {
        router.fundAndRoute(1_000 * U, bytes32(uint256(1)));
        _eq(vault.unallocatedRewards(), 800 * U);
        _eq(vault.totalPrincipal(), 0);
        _eq(splitter.totalClaimable(), 200 * U);
        _eq(token.balanceOf(address(vault)), 800 * U);
        _eq(token.balanceOf(address(splitter)), 200 * U);
        _eq(token.balanceOf(address(router)), 0);
        _eq(splitter.claimable(wallets[0]), 40 * U);
        for (uint256 i = 1; i < 11; ++i) {
            _eq(splitter.claimable(wallets[i]), 16 * U);
        }
        require(vault.isSolvent() && splitter.isSolvent(), "Both destinations solvent");
        _eq(router.totalRevenueFunded(), 1_000 * U);
        _eq(router.totalVaultReservesFunded(), 800 * U);
        _eq(router.totalWalletPoolFunded(), 200 * U);
    }

    function testUserDepositRemainsOneHundredPercentInVault() public {
        vm.prank(ALICE);
        vault.deposit(100 * U, address(0));
        _eq(vault.totalPrincipal(), 100 * U);
        _eq(token.balanceOf(address(vault)), 100 * U);
        _eq(vault.unallocatedRewards(), 0);
        _eq(splitter.totalClaimable(), 0);

        router.fundAndRoute(1_000 * U, bytes32(uint256(2)));
        _eq(token.balanceOf(address(vault)), 900 * U);
        _eq(vault.totalPrincipal(), 100 * U);
        _eq(vault.unallocatedRewards(), 800 * U);
        _eq(splitter.totalClaimable(), 200 * U);
        uint256 balanceBefore = token.balanceOf(ALICE);
        vm.prank(ALICE);
        vault.withdrawPrincipal(100 * U);
        _eq(token.balanceOf(ALICE), balanceBefore + 100 * U);
        _eq(vault.totalPrincipal(), 0);
        _eq(token.balanceOf(address(vault)), 800 * U);
        require(vault.isSolvent(), "Full principal was protected");
    }

    function testRoutersCannotFundIfPermissionMissingAndMustBeAtomic() public {
        splitter.revokeRole(splitter.FUNDER_ROLE(), address(router));
        uint256 balanceBefore = token.balanceOf(address(this));
        _expectRouterRevert(
            abi.encodeCall(NexoraRevenueRouter.fundAndRoute, (100 * U, bytes32(uint256(3))))
        );
        _eq(token.balanceOf(address(this)), balanceBefore);
        _eq(token.balanceOf(address(router)), 0);
        _eq(token.balanceOf(address(vault)), 0);
        _eq(token.balanceOf(address(splitter)), 0);
        _eq(vault.unallocatedRewards(), 0);
        _eq(splitter.totalClaimable(), 0);
        require(!router.usedEvidenceIds(bytes32(uint256(3))), "Report was used after revert");
    }

    function testOnlyAuthorizedRevenueFunderCanRoute() public {
        vm.prank(OUTSIDER);
        _expectRouterRevert(
            abi.encodeCall(NexoraRevenueRouter.fundAndRoute, (100 * U, bytes32(uint256(4))))
        );
        _eq(vault.unallocatedRewards(), 0);
        _eq(splitter.totalClaimable(), 0);
    }

    function testNoDuplicateOrEmptyAccountingEvidence() public {
        _expectRouterRevert(abi.encodeCall(
            NexoraRevenueRouter.fundAndRoute, (100 * U, bytes32(0))
        ));
        router.fundAndRoute(100 * U, bytes32(uint256(5)));
        _expectRouterRevert(abi.encodeCall(
            NexoraRevenueRouter.fundAndRoute, (100 * U, bytes32(uint256(5)))
        ));
        _eq(vault.unallocatedRewards(), 80 * U);
        _eq(splitter.totalClaimable(), 20 * U);
    }

    function testEmergencyPauseStopsNewRoutingButNotExistingClaims() public {
        router.fundAndRoute(100 * U, bytes32(uint256(6)));
        router.pause();
        _expectRouterRevert(abi.encodeCall(
            NexoraRevenueRouter.fundAndRoute, (100 * U, bytes32(uint256(7)))
        ));
        vm.prank(wallets[0]);
        splitter.claim();
        _eq(token.balanceOf(wallets[0]), 4 * U);
        require(vault.isSolvent() && splitter.isSolvent(), "Reserve remains backed");
    }

    function testFuzz_EveryUnitIsEitherVaultReserveOrWalletPool(uint96 raw) public {
        uint256 amount = 1 * U + uint256(raw) % (100_000 * U);
        (uint256 expectedVault, uint256 expectedWallets) = router.previewSplit(amount);
        _eq(expectedVault + expectedWallets, amount);

        router.fundAndRoute(amount, bytes32(uint256(1337)));
        _eq(vault.unallocatedRewards(), expectedVault);
        _eq(splitter.totalClaimable(), expectedWallets);
        _eq(token.balanceOf(address(router)), 0);
        require(vault.isSolvent() && splitter.isSolvent(), "All routed funds backed");
    }

    function testMultipleReportsAccumulate80And20WithoutLeaks() public {
        router.fundAndRoute(250 * U, bytes32(uint256(8)));
        router.fundAndRoute(750 * U, bytes32(uint256(9)));
        _eq(vault.unallocatedRewards(), 800 * U);
        _eq(splitter.totalClaimable(), 200 * U);
        _eq(router.totalRevenueFunded(), 1_000 * U);
        require(vault.isSolvent() && splitter.isSolvent(), "Funded");
    }

    function testDestinationAssetMustMatch() public {
        MockUSDT wrongAsset = new MockUSDT();
        try new NexoraRevenueRouter(
            address(wrongAsset), address(vault), address(splitter), address(this), address(this)
        ) {
            revert("Mismatched asset accepted");
        } catch {}
    }
}
