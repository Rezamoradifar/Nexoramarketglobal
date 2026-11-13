// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraEntryAllocationPreview} from "../src/NexoraEntryAllocationPreview.sol";

/** Model-2 receipts only: not user principal custody or live payouts. */
contract NexoraEntryAllocationPreviewTest {
    NexoraEntryAllocationPreview private policy;
    uint256 private constant U = 1e18;

    function setUp() public {
        policy = new NexoraEntryAllocationPreview();
    }

    function _eq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "Mismatch");
    }

    function testUserSeesGrossOneThousandButReceivesNetEightHundred() public view {
        NexoraEntryAllocationPreview.AccountReceipt memory a = policy.preview(1_000 * U);
        _eq(a.grossAmountRecorded, 1_000 * U);
        _eq(a.planReferenceAmount, 1_000 * U);
        _eq(a.netPrincipalCredited, 800 * U);
        _eq(a.ownerAllocation, 60 * U);
        _eq(a.companyAllocationEach, 14 * U);
        _eq(a.companyAllocationTotal, 140 * U);
        _eq(
            a.netPrincipalCredited + a.ownerAllocation + a.companyAllocationTotal,
            1_000 * U
        );
        _eq(policy.WITHDRAWAL_FEE_BPS(), 0);
    }

    function testReinvestReceiptShowsGrossOneHundredAndNetEighty() public view {
        NexoraEntryAllocationPreview.AccountReceipt memory a = policy.preview(100 * U);
        _eq(a.grossAmountRecorded, 100 * U);
        _eq(a.planReferenceAmount, 100 * U);
        _eq(a.netPrincipalCredited, 80 * U);
        _eq(a.ownerAllocation, 6 * U);
        _eq(a.companyAllocationEach, 14 * U / 10);
        _eq(a.companyAllocationTotal, 14 * U);
    }

    function testGrossPlanReferenceDoesNotMakeGrossRedeemable() public view {
        NexoraEntryAllocationPreview.AccountReceipt memory a = policy.preview(1_000 * U);
        (uint256 dailyCap, uint256 remaining, uint256 actual) =
            policy.previewWithdrawable(
                a.grossAmountRecorded, 0, a.netPrincipalCredited
            );
        _eq(dailyCap, 200 * U);
        _eq(remaining, 200 * U);
        _eq(actual, 200 * U);
        // Only 800 total is backed principal; 1,000 is historical deposit.
        _eq(a.netPrincipalCredited, 800 * U);
        (, , actual) = policy.previewWithdrawable(a.grossAmountRecorded, 0, 0);
        _eq(actual, 0);
        (, remaining, actual) = policy.previewWithdrawable(
            a.grossAmountRecorded, 150 * U, 30 * U
        );
        _eq(remaining, 50 * U);
        _eq(actual, 30 * U);
    }

    function testConditionalRewardReferenceIsNotActualReward() public view {
        NexoraEntryAllocationPreview.AccountReceipt memory a = policy.preview(1_000 * U);
        _eq(policy.previewConditionalRewardCeiling(a.planReferenceAmount, 100), 10 * U);
        // The calculator creates no token or reward liability.
    }

    function testRoundingAlwaysBenefitsNetUserPrincipal() public view {
        for (uint256 i = 1; i < 200; ++i) {
            NexoraEntryAllocationPreview.AccountReceipt memory a = policy.preview(i);
            _eq(
                a.netPrincipalCredited + a.ownerAllocation + a.companyAllocationTotal,
                i
            );
            require(a.ownerAllocation <= i * 600 / 10_000, "owner overpaid");
            require(a.companyAllocationEach <= i * 140 / 10_000, "company overpaid");
            require(a.netPrincipalCredited >= i * 8 / 10, "net less than disclosed");
        }
    }

    function testFuzz_AllTokensAccountedAndGrossNotDuplicated(uint96 raw) public view {
        uint256 gross = uint256(raw) + 1;
        NexoraEntryAllocationPreview.AccountReceipt memory a = policy.preview(gross);
        _eq(a.grossAmountRecorded, gross);
        _eq(a.netPrincipalCredited + a.ownerAllocation + a.companyAllocationTotal, gross);
        _eq(a.companyAllocationTotal, a.companyAllocationEach * 10);
        require(a.netPrincipalCredited >= gross * 8 / 10, "principal was diluted more");
    }

    function testFuzz_ActualWithdrawalIsBoundedByRealBalance(uint96 raw, uint96 spent, uint96 balance) public view {
        uint256 gross = uint256(raw);
        uint256 used = uint256(spent);
        uint256 matured = uint256(balance);
        (uint256 dailyCap, uint256 remaining, uint256 actual) =
            policy.previewWithdrawable(gross, used, matured);
        _eq(dailyCap, gross / 5);
        require(remaining <= dailyCap, "over cap");
        require(actual <= remaining && actual <= matured, "backing exceeded");
    }

    function testZeroGrossRejected() public {
        bool reverted;
        try policy.preview(0) returns (NexoraEntryAllocationPreview.AccountReceipt memory) {
            reverted = false;
        } catch { reverted = true; }
        require(reverted, "zero gross accepted");
    }
}
