// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Model2DeepFixture} from "./NexoraModel2DeepValidation.t.sol";

/** Compare the max-heap against an independently scanned referral set. */
contract NexoraModel2HeapFuzzTest is Model2DeepFixture {
    function testFuzz_BranchMaximumMatchesScanAfterMixedUpdates(uint256 randomSeed) public {
        seed(A, 500 * U, address(0));
        for (uint256 i; i < 12; ++i) seed(address(uint160(0x6000 + i)), (100 + 25 * i) * U, A);
        vm.warp(T + 90 days);
        for (uint256 step; step < 32; ++step) {
            randomSeed = uint256(keccak256(abi.encode(randomSeed, step)));
            address member = address(uint160(0x6000 + randomSeed % 12));
            uint256 amount = (1 + (randomSeed >> 16) % 5) * U;
            (uint256 matured,) = vault.principalTrancheAt(member, 0);
            if ((randomSeed & 1) == 0 || matured < amount || vault.remainingWithdrawalCap(member) < amount) {
                seed(member, amount, A);
            } else {
                vm.prank(member); vault.withdrawPrincipal(amount);
            }
            uint256 largest;
            uint256 sum;
            for (uint256 i; i < 12; ++i) {
                address child = address(uint160(0x6000 + i));
                uint256 actual = vault.branchVolume(A, child);
                eq(actual, vault.getAccount(child).grossPositionBasis);
                sum += actual;
                if (actual > largest) largest = actual;
            }
            eq(vault.teamVolume(A), sum);
            eq(vault.largestBranchVolume(A), largest);
            vm.warp(T + (91 + step) * 1 days);
        }
        checkLedgers();
    }
}
