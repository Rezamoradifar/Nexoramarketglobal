// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraWithdrawalPolicyPreview} from "../src/NexoraWithdrawalPolicyPreview.sol";

/**
 * Preview-only unit and fuzz tests. DOES NOT assert a period definition;
 * that policy remains undefined and cannot be used to enforce withdrawals.
 */
contract NexoraWithdrawalPolicyPreviewTest {
    NexoraWithdrawalPolicyPreview private policy;

    uint256 private constant UNIT = 1e18;

    function setUp() public {
        policy = new NexoraWithdrawalPolicyPreview();
    }

    function _eq(uint256 actual, uint256 expected) private pure {
        require(actual == expected, "Amount mismatch");
    }

    function testTwentyPercentOfOneThousandDepositedIsTwoHundred() public view {
        (uint256 cap, uint256 remaining) =
            policy.previewRemainingWithdrawalCap(1_000 * UNIT, 0);
        _eq(cap, 200 * UNIT);
        _eq(remaining, 200 * UNIT);
    }

    function testMultipleWithdrawalsInTheSamePeriodUseCumulativeAmount() public view {
        (uint256 cap, uint256 remaining) =
            policy.previewRemainingWithdrawalCap(1_000 * UNIT, 120 * UNIT);
        _eq(cap, 200 * UNIT);
        _eq(remaining, 80 * UNIT);

        (, remaining) = policy.previewRemainingWithdrawalCap(1_000 * UNIT, 199 * UNIT);
        _eq(remaining, 1 * UNIT);
        (, remaining) = policy.previewRemainingWithdrawalCap(1_000 * UNIT, 200 * UNIT);
        _eq(remaining, 0);
        (, remaining) = policy.previewRemainingWithdrawalCap(1_000 * UNIT, 300 * UNIT);
        _eq(remaining, 0);
    }

    function testZeroBalanceAndTokenUnitRounding() public view {
        (uint256 cap, uint256 remaining) =
            policy.previewRemainingWithdrawalCap(0, 0);
        _eq(cap, 0);
        _eq(remaining, 0);

        (cap, remaining) = policy.previewRemainingWithdrawalCap(9, 0);
        _eq(cap, 1);
        _eq(remaining, 1);
        (cap, remaining) = policy.previewRemainingWithdrawalCap(4, 0);
        _eq(cap, 0);
        _eq(remaining, 0);
    }

    function testReinvestPartOfFundedRewardConservesUserLiability() public view {
        uint256 reward = 200 * UNIT;
        (uint256 remaining, uint256 newPrincipal) =
            policy.previewReinvest(reward, 70 * UNIT);
        _eq(remaining, 130 * UNIT);
        _eq(newPrincipal, 70 * UNIT);
        _eq(remaining + newPrincipal, reward);
    }

    function testReinvestDoesNotSilentlyGrowExternalDepositCap() public view {
        (uint256 beforeCap,) = policy.previewRemainingWithdrawalCap(1_000 * UNIT, 0);
        (, uint256 newPrincipal) = policy.previewReinvest(200 * UNIT, 200 * UNIT);
        // Reinvested amount cannot simply be treated as a new external deposit.
        (uint256 afterCap,) = policy.previewRemainingWithdrawalCap(1_000 * UNIT, 0);
        _eq(beforeCap, 200 * UNIT);
        _eq(newPrincipal, 200 * UNIT);
        _eq(afterCap, beforeCap);
    }

    function testReinvestZeroOrMoreThanFundedRewardsIsRejected() public {
        bool rejected;
        try policy.previewReinvest(100 * UNIT, 0) returns (uint256, uint256) {
            rejected = false;
        } catch {
            rejected = true;
        }
        require(rejected, "Zero reinvest accepted");

        try policy.previewReinvest(100 * UNIT, 101 * UNIT) returns (uint256, uint256) {
            rejected = false;
        } catch {
            rejected = true;
        }
        require(rejected, "Unfunded reinvest accepted");
    }

    function testFuzz_CapNeverExceedsOneFifth(uint96 raw, uint96 withdrawn) public view {
        uint256 deposited = uint256(raw);
        uint256 previouslyWithdrawn = uint256(withdrawn);
        (uint256 cap, uint256 remaining) =
            policy.previewRemainingWithdrawalCap(deposited, previouslyWithdrawn);
        _eq(cap, deposited / 5);
        require(remaining <= cap, "Remaining exceeds 20% allowance");
        if (previouslyWithdrawn >= cap) _eq(remaining, 0);
        else _eq(remaining + previouslyWithdrawn, cap);
    }

    function testFuzz_ReinvestNeverCreatesLiability(uint96 available, uint96 amount) public view {
        uint256 reward = uint256(available) + 1;
        uint256 reinvestAmount = uint256(amount) % reward + 1;
        (uint256 remaining, uint256 newPrincipal) =
            policy.previewReinvest(reward, reinvestAmount);
        _eq(remaining + newPrincipal, reward);
    }
}
