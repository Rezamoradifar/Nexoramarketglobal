// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraProfitVault} from "../src/NexoraProfitVault.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {NexoraRevenueRouter} from "../src/NexoraRevenueRouter.sol";
import {MockUSDT} from "./MockUSDT.sol";

interface VmBeneficiaryManifest {
    function readFile(string calldata filePath) external view returns (string memory);
    function parseJsonAddressArray(string calldata json, string calldata key)
        external pure returns (address[] memory);
    function parseJsonUint(string calldata json, string calldata key)
        external pure returns (uint256);
    function prank(address sender) external;
    function warp(uint256 timestamp) external;
}

/**
 * This test loads the 11 REAL PUBLIC WALLET ADDRESSES provided by the owner
 * from config/beneficiary-wallets.candidate.json, preserving their order.
 * No user funds and no real tokens are handled by this test.
 *
 * A valid address or prank in a test DOES NOT prove wallet ownership.
 */
contract NexoraConfiguredBeneficiariesTest {
    VmBeneficiaryManifest private constant vm =
        VmBeneficiaryManifest(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant U = 1e18;
    address private constant USER = address(0xA11CE);

    MockUSDT private token;
    NexoraProfitVault private vault;
    NexoraRevenueSplitter private splitter;
    NexoraRevenueRouter private router;
    address[11] private recipients;

    function setUp() public {
        vm.warp(120 days);
        string memory manifest = vm.readFile("config/beneficiary-wallets.candidate.json");
        address[] memory wallets =
            vm.parseJsonAddressArray(manifest, ".constructorWallets");
        require(wallets.length == 11, "Exactly 11 wallets required");

        require(vm.parseJsonUint(manifest, ".revenueSplitBps.vaultRewardReserve") == 8_000,
            "Reserve ratio changed");
        require(vm.parseJsonUint(manifest, ".revenueSplitBps.owner") == 600,
            "Owner ratio changed");
        require(vm.parseJsonUint(manifest, ".revenueSplitBps.eachCompany") == 140,
            "Company ratio changed");

        for (uint256 i; i < 11; ++i) {
            require(wallets[i] != address(0), "Zero beneficiary");
            for (uint256 j; j < i; ++j) {
                require(wallets[i] != wallets[j], "Duplicate beneficiary");
            }
            recipients[i] = wallets[i];
        }

        token = new MockUSDT();
        vault = new NexoraProfitVault(
            address(token), address(this), address(this), address(this)
        );
        splitter = new NexoraRevenueSplitter(
            address(token), address(this), address(this), recipients
        );
        router = new NexoraRevenueRouter(
            address(token), address(vault), address(splitter), address(this), address(this)
        );
        vault.grantRole(vault.FUNDER_ROLE(), address(router));
        splitter.grantRole(splitter.FUNDER_ROLE(), address(router));
        vault.revokeRole(vault.FUNDER_ROLE(), address(this));
        splitter.revokeRole(splitter.FUNDER_ROLE(), address(this));

        token.mint(address(this), 2_000 * U); // TEST revenue, not a live balance
        token.approve(address(router), type(uint256).max);
        token.mint(USER, 1_000 * U); // TEST principal, not a real deposit
        vm.prank(USER);
        token.approve(address(vault), type(uint256).max);
    }

    function testElevenSuppliedAddressesAndFixedWeightsMatchSplitter() public view {
        require(splitter.payoutWallets(0) == recipients[0], "Owner address wrong");
        require(splitter.shareWeights(0) == 30, "Owner weight wrong");
        for (uint256 i = 1; i < 11; ++i) {
            require(splitter.payoutWallets(i) == recipients[i],
                "Corporate wallet sequence altered");
            require(splitter.shareWeights(i) == 7, "Corporate wallet weight wrong");
        }
        require(splitter.POOL_WEIGHT_DENOMINATOR() == 100,
            "Pool weights do not total 100");
    }

    function testExactWalletPayoutsAndUserPrincipalAreSeparated() public {
        // Only a user's own deposit establishes their principal account.
        vm.prank(USER);
        vault.deposit(1_000 * U, address(0));
        require(vault.getAccount(USER).principal == 1_000 * U,
            "User deposit changed by company payout");

        // The 80/6/14 split is applied to INDEPENDENT revenue, not that deposit.
        router.fundAndRoute(1_000 * U, bytes32(uint256(18)));
        require(vault.unallocatedRewards() == 800 * U, "Reserve should get 800");
        require(vault.totalPrincipal() == 1_000 * U, "User principal touched");
        require(splitter.claimable(recipients[0]) == 60 * U,
            "Owner should get 60");
        for (uint256 i = 1; i < 11; ++i) {
            require(splitter.claimable(recipients[i]) == 14 * U,
                "Each corporate wallet should get 14");
        }
        require(token.balanceOf(address(vault)) == 1_800 * U,
            "Vault must hold principal plus funded reserve");
        require(token.balanceOf(address(splitter)) == 200 * U,
            "Corporate balances must be backed");
        require(vault.isSolvent() && splitter.isSolvent(),
            "No unfunded liabilities permitted");
    }

    function testCompanyCannotWithdrawAnotherUsersPrincipal() public {
        vm.prank(USER);
        vault.deposit(1_000 * U, address(0));

        vm.warp(block.timestamp + 90 days);
        (bool success,) = address(vault).call(
            abi.encodeCall(NexoraProfitVault.withdrawPrincipal, (200 * U))
        );
        require(!success, "Unrelated caller withdrew user principal");

        vm.prank(recipients[0]);
        (success,) = address(vault).call(
            abi.encodeCall(NexoraProfitVault.withdrawPrincipal, (200 * U))
        );
        require(!success, "Owner wallet withdrew user principal");

        vm.prank(recipients[1]);
        (success,) = address(vault).call(
            abi.encodeCall(NexoraProfitVault.withdrawPrincipal, (200 * U))
        );
        require(!success, "Company wallet withdrew user principal");
    }
}
