// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraProfitVault} from "../src/NexoraProfitVault.sol";
import {MockUSDT} from "./MockUSDT.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
}

contract NexoraProfitVaultTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant U = 1e18;

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA201);
    address private constant DAVE = address(0xDA7E);
    address private constant EVE = address(0xE7E);

    MockUSDT private token;
    NexoraProfitVault private vault;

    function setUp() public {
        vm.warp(100 days);
        token = new MockUSDT();
        vault = new NexoraProfitVault(address(token), address(this), address(this), address(this));
        address[5] memory users = [ALICE, BOB, CAROL, DAVE, EVE];
        for (uint256 i; i < users.length; ++i) {
            token.mint(users[i], 100_000 * U);
            vm.prank(users[i]);
            token.approve(address(vault), type(uint256).max);
        }
        token.mint(address(this), 100_000 * U);
        token.approve(address(vault), type(uint256).max);
    }

    function _deposit(address member, uint256 amount, address parent) private {
        vm.prank(member);
        vault.deposit(amount, parent);
    }

    function _assertEq(uint256 a, uint256 b) private pure {
        require(a == b, "Not equal");
    }

    function _expectFailure(bytes memory data) private {
        (bool success,) = address(vault).call(data);
        require(!success, "Expected operation to revert");
    }

    function testPrincipalIsWithdrawableWhilePaused() public {
        _deposit(ALICE, 100 * U, address(0));
        _assertEq(vault.totalPrincipal(), 100 * U);
        _assertEq(vault.unallocatedRewards(), 0);

        vault.pause();
        uint256 beforeBalance = token.balanceOf(ALICE);
        vm.prank(ALICE);
        vault.withdrawPrincipal(40 * U);
        _assertEq(token.balanceOf(ALICE), beforeBalance + 40 * U);
        _assertEq(vault.totalPrincipal(), 60 * U);
        require(vault.isSolvent(), "Vault must remain solvent");
        vm.prank(ALICE);
        _expectFailure(abi.encodeCall(NexoraProfitVault.deposit, (10 * U, address(0))));
    }

    function testNotEligibleUntil24Hours() public {
        _deposit(ALICE, 100 * U, address(0));
        _assertEq(vault.tierBps(ALICE), 0);
        vm.warp(block.timestamp + 1 days);
        _assertEq(vault.tierBps(ALICE), 100);
        _deposit(ALICE, 1 * U, address(0));
        _assertEq(vault.tierBps(ALICE), 0);
    }

    function testDirectNeedsMaturityAndTopUpResetsIt() public {
        _deposit(ALICE, 100 * U, address(0));
        _deposit(BOB, 100 * U, ALICE);
        _expectFailure(abi.encodeCall(NexoraProfitVault.syncDirect, (BOB)));
        vm.warp(block.timestamp + 1 days);
        vault.syncDirect(BOB);
        _assertEq(vault.getAccount(ALICE).activeDirects, 1);
        _deposit(BOB, 1 * U, ALICE);
        _assertEq(vault.getAccount(ALICE).activeDirects, 0);
        _expectFailure(abi.encodeCall(NexoraProfitVault.syncDirect, (BOB)));
        vm.warp(block.timestamp + 1 days);
        vault.syncDirect(BOB);
        _assertEq(vault.getAccount(ALICE).activeDirects, 1);
    }

    function testBalancedBranchesUnlockTier() public {
        _deposit(ALICE, 500 * U, address(0));
        _deposit(BOB, 1_250 * U, ALICE);
        _deposit(CAROL, 1_250 * U, ALICE);
        vm.warp(block.timestamp + 1 days);
        vault.syncDirect(BOB);
        vault.syncDirect(CAROL);
        _assertEq(vault.teamVolume(ALICE), 2_500 * U);
        _assertEq(vault.tierBps(ALICE), 125);
        vm.prank(CAROL);
        vault.withdrawPrincipal(1_000 * U);
        _assertEq(vault.tierBps(ALICE), 100);
    }

    function testOneDominantBranchCannotUnlockTier() public {
        _deposit(ALICE, 500 * U, address(0));
        _deposit(BOB, 2_000 * U, ALICE);
        _deposit(CAROL, 500 * U, ALICE);
        vm.warp(block.timestamp + 1 days);
        vault.syncDirect(BOB);
        vault.syncDirect(CAROL);
        _assertEq(vault.teamVolume(ALICE), 2_500 * U);
        _assertEq(vault.tierBps(ALICE), 100);
    }

    function testDepositDoesNotCreateRewards() public {
        _deposit(ALICE, 100 * U, address(0));
        vm.warp(block.timestamp + 1 days);
        _expectFailure(abi.encodeCall(NexoraProfitVault.allocateReward, (ALICE, 1 * U, bytes32(uint256(1)))));
        _assertEq(vault.unallocatedRewards(), 0);
        _assertEq(vault.totalClaimableRewards(), 0);
        require(vault.isSolvent(), "Vault must remain solvent");
    }

    function testDailyCapAnd24HourInterval() public {
        _deposit(ALICE, 100 * U, address(0));
        vm.warp(block.timestamp + 1 days);
        vault.fundRewards(4 * U);
        _expectFailure(abi.encodeCall(NexoraProfitVault.allocateReward, (ALICE, 2 * U, bytes32(uint256(1)))));
        vault.allocateReward(ALICE, 1 * U, bytes32(uint256(1)));
        _expectFailure(abi.encodeCall(NexoraProfitVault.allocateReward, (ALICE, 1 * U, bytes32(uint256(2)))));
        vm.warp(block.timestamp + 1 days);
        vault.allocateReward(ALICE, 1 * U, bytes32(uint256(2)));
        _assertEq(vault.totalClaimableRewards(), 2 * U);
    }

    function testThreeLevelReferralsArePreFunded() public {
        _deposit(ALICE, 100 * U, address(0));
        _deposit(BOB, 100 * U, ALICE);
        _deposit(CAROL, 100 * U, BOB);
        _deposit(DAVE, 100 * U, CAROL);
        vm.warp(block.timestamp + 1 days);
        vault.syncDirect(BOB);
        vault.syncDirect(CAROL);
        vault.syncDirect(DAVE);
        vault.fundRewards(2 * U);
        vault.allocateReward(DAVE, 1 * U, bytes32(uint256(111)));
        _assertEq(vault.getAccount(DAVE).baseRewards, 1 * U);
        _assertEq(vault.getAccount(CAROL).referralRewards, 15 * U / 100);
        _assertEq(vault.getAccount(BOB).referralRewards, 7 * U / 100);
        _assertEq(vault.getAccount(ALICE).referralRewards, 3 * U / 100);
        _assertEq(vault.unallocatedRewards(), 75 * U / 100);
        _assertEq(vault.totalClaimableRewards(), 125 * U / 100);

        uint256 beforeBalance = token.balanceOf(DAVE);
        vm.prank(DAVE);
        vault.claimRewards();
        _assertEq(token.balanceOf(DAVE), beforeBalance + 1 * U);
        require(vault.isSolvent(), "Vault must remain solvent");
    }

    function testThirdPartyCannotTakePrincipalOrChangeReferrer() public {
        _deposit(ALICE, 100 * U, address(0));
        vm.prank(BOB);
        _expectFailure(abi.encodeCall(NexoraProfitVault.withdrawPrincipal, (1 * U)));
        vm.prank(ALICE);
        _expectFailure(abi.encodeCall(NexoraProfitVault.deposit, (1 * U, BOB)));
        require(vault.isSolvent(), "Vault must remain solvent");
    }

    function testAllocatorRoleRequired() public {
        _deposit(ALICE, 100 * U, address(0));
        vm.warp(block.timestamp + 1 days);
        vault.fundRewards(2 * U);
        vm.prank(BOB);
        _expectFailure(abi.encodeCall(NexoraProfitVault.allocateReward, (ALICE, 1 * U, bytes32(uint256(9)))));
        _assertEq(vault.unallocatedRewards(), 2 * U);
    }

    function testDirectParentCannotBeSelfOrFutureMember() public {
        vm.prank(ALICE);
        _expectFailure(abi.encodeCall(NexoraProfitVault.deposit, (100 * U, ALICE)));
        vm.prank(ALICE);
        _expectFailure(abi.encodeCall(NexoraProfitVault.deposit, (100 * U, BOB)));
        _assertEq(vault.totalPrincipal(), 0);
    }
}
