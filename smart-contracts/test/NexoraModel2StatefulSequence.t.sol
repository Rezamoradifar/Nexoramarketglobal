// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Model2DeepFixture} from "./NexoraModel2DeepValidation.t.sol";
import {NexoraModel2Vault} from "../src/NexoraModel2Vault.sol";
import {NexoraModel2Core} from "../src/NexoraModel2Core.sol";

/** A randomized sequence is one scenario, not a real chain transaction. */
contract NexoraModel2StatefulSequenceTest is Model2DeepFixture {
    struct Paid { uint256 at; uint256 amount; }
    mapping(address => Paid[]) private paid;
    uint256 private successfulCalls;

    function record(address who, uint256 amount) private {
        paid[who].push(Paid(vm.getBlockTimestamp(), amount));
        ++successfulCalls;
    }

    function checkIndependentHistoryAndReferrals() private view {
        uint256 now_ = vm.getBlockTimestamp();
        for (uint256 i; i < actors.length; ++i) {
            address who = actors[i];
            uint256 recent;
            for (uint256 p; p < paid[who].length; ++p)
                if (paid[who][p].at > now_ - 1 days) recent += paid[who][p].amount;
            eq(vault.withdrawnInLast24Hours(who), recent);
            uint256 ceiling = vault.externalDepositBasis(who) / 5;
            require(recent <= ceiling, "independent rolling limit violated");
            eq(vault.remainingWithdrawalCap(who), ceiling - recent);
            uint256 team;
            uint256 activeChildren;
            for (uint256 j; j < actors.length; ++j) {
                NexoraModel2Core.Account memory a = vault.getAccount(actors[j]);
                if (a.referrer == who && a.countedInParent) {
                    ++activeChildren;
                    require(a.grossPositionBasis >= 100 * U && now_ >= a.lastDepositAt + 1 days,
                        "premature or insolvent direct eligibility");
                }
                address ancestor = a.referrer;
                for (uint256 depth; depth < 3 && ancestor != address(0); ++depth) {
                    if (ancestor == who) team += a.grossPositionBasis;
                    ancestor = vault.getAccount(ancestor).referrer;
                }
            }
            eq(vault.teamVolume(who), team);
            eq(vault.getAccount(who).activeDirects, activeChildren);
        }
        checkLedgers();
    }

    function maturedNet(address who) private view returns (uint256 sum) {
        for (uint256 i; i < vault.principalTrancheCount(who); ++i) {
            (uint256 amount, uint64 unlockAt) = vault.principalTrancheAt(who, i);
            if (vm.getBlockTimestamp() >= unlockAt) sum += amount;
        }
    }

    function exercise(address who, uint256 choice, uint256 rnd, uint256 step) private {
        uint256 now_ = vm.getBlockTimestamp();
        NexoraModel2Core.Account memory a = vault.getAccount(who);
        if (choice == 0 && !vault.paused() && !splitter.paused()) {
            uint256 topup = (1 + rnd % 50) * U;
            if (a.grossPositionBasis + topup <= 50_000 * U) { seed(who, topup, address(0)); ++successfulCalls; }
        } else if (choice == 1) {
            vm.warp(now_ + 1 + rnd % (20 days)); ++successfulCalls;
        } else if (choice == 2 && !vault.paused()) {
            uint256 rate = vault.tierBps(who);
            if (rate != 0 && (a.lastCreditAt == 0 || now_ >= a.lastCreditAt + 1 days)) {
                uint256 maximum = a.grossPositionBasis * rate / 10_000;
                if (maximum != 0) {
                    uint256 amount = 1 + rnd % maximum;
                    if (vault.unallocatedRewards() >= amount * 125 / 100 + 10) {
                        vault.allocateReward(who, amount, keccak256(abi.encode("STATEFUL", step, rnd)));
                        ++successfulCalls;
                    }
                }
            }
        } else if (choice == 3 && !vault.paused() && !splitter.paused()) {
            uint256 available = a.baseRewards + a.referralRewards;
            if (available != 0) {
                uint256 amount = 1 + rnd % available;
                if (a.grossPositionBasis + amount <= 50_000 * U) {
                    vm.prank(who); vault.reinvestRewards(amount); ++successfulCalls;
                }
            }
        } else if (choice == 4) {
            uint256 maximum = maturedNet(who);
            uint256 cap = vault.remainingWithdrawalCap(who);
            if (cap < maximum) maximum = cap;
            if (maximum != 0) {
                uint256 amount = 1 + rnd % maximum;
                vm.prank(who); vault.withdrawPrincipal(amount); record(who, amount);
            }
        } else if (choice == 5) {
            uint256 available = a.baseRewards + a.referralRewards;
            uint256 cap = vault.remainingWithdrawalCap(who);
            if (available != 0 && cap != 0 && now_ >= a.firstDepositAt + 90 days) {
                vm.prank(who); uint256 amount = vault.claimRewards();
                eq(amount, available < cap ? available : cap); record(who, amount);
            }
        } else if (choice == 6) {
            if (a.referrer != address(0) && !a.countedInParent && a.grossPositionBasis >= 100 * U && now_ >= a.lastDepositAt + 1 days) {
                vault.syncDirect(who); ++successfulCalls;
            }
        } else if (choice == 7) {
            address beneficiary = beneficiaries[rnd % 11];
            if (splitter.claimable(beneficiary) != 0) { vm.prank(beneficiary); splitter.claim(); ++successfulCalls; }
        } else if (choice == 8) {
            if (vault.paused()) vault.unpause(); else vault.pause(); ++successfulCalls;
        } else if (choice == 9) {
            if (splitter.paused()) splitter.unpause(); else splitter.pause(); ++successfulCalls;
        }
    }

    function testFuzz_StatefulActionsPreserveBackingGrossNetTeamsAndRollingLimits(uint256 randomSeed) public {
        seed(A, 1000 * U, address(0)); seed(B, 1000 * U, A);
        seed(C, 1000 * U, B); seed(D, 1000 * U, C);
        vault.fundRewards(100_000 * U);
        vm.warp(T + 90 days);
        // Mandatory non-vacuous lifecycle spine before random operations.
        vault.allocateReward(A, 10 * U, bytes32(uint256(777)));
        vm.prank(A); vault.reinvestRewards(5 * U);
        vm.prank(A); vault.withdrawPrincipal(100 * U); record(A, 100 * U);
        vm.prank(A); uint256 claimed = vault.claimRewards(); record(A, claimed);
        eq(claimed, 5 * U);
        checkIndependentHistoryAndReferrals();
        for (uint256 step; step < 48; ++step) {
            randomSeed = uint256(keccak256(abi.encode(randomSeed, step)));
            address who = actors[(randomSeed >> 8) % 4];
            exercise(who, randomSeed % 10, randomSeed >> 32, step);
            checkIndependentHistoryAndReferrals();
        }
        require(successfulCalls >= 2, "sequence never exercised real exits");
    }
}
