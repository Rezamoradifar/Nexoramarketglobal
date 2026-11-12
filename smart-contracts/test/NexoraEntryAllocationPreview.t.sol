// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraEntryAllocationPreview} from "../src/NexoraEntryAllocationPreview.sol";

/**
 * Tests ONLY math/disclosure of a proposed entry + reinvest charge.
 * Does not implement or authorize live transfers from depositors.
 */
contract NexoraEntryAllocationPreviewTest {
    NexoraEntryAllocationPreview private policy;
    uint256 private constant U = 1e18;

    function setUp() public {
        policy = new NexoraEntryAllocationPreview();
    }

    function _eq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "Mismatch");
    }

    function testOneThousandDepositHasOnlyEightHundredNetPrincipal() public view {
        NexoraEntryAllocationPreview.Allocation memory a = policy.preview(1_000 * U);
        _eq(a.netPrincipal, 800 * U);
        _eq(a.ownerCharge, 60 * U);
        _eq(a.companyChargeEach, 14 * U);
        _eq(a.roundingToNetPrincipal, 0);
        _eq(a.netPrincipal + a.ownerCharge + 10 * a.companyChargeEach, 1_000 * U);
        _eq(policy.previewDailyCap(a.netPrincipal), 160 * U);
        _eq(policy.WITHDRAWAL_FEE_BPS(), 0);
    }

    function testOneHundredFundedProfitReinvestHasEightyNetNewPrincipal() public view {
        NexoraEntryAllocationPreview.Allocation memory a = policy.preview(100 * U);
        _eq(a.netPrincipal, 80 * U);
        _eq(a.ownerCharge, 6 * U);
        _eq(a.companyChargeEach, 14 * U / 10);
        _eq(a.netPrincipal + a.ownerCharge + 10 * a.companyChargeEach, 100 * U);
    }

    function testNoRoundoffDustPaidToInsiders() public view {
        NexoraEntryAllocationPreview.Allocation memory a = policy.preview(101);
        _eq(a.ownerCharge, 6);
        _eq(a.companyChargeEach, 1);
        _eq(a.netPrincipal, 85);
        _eq(a.netPrincipal + a.ownerCharge + 10 * a.companyChargeEach, 101);
    }

    function testInsiderChargeCannotExceed20PercentOfGross() public view {
        for (uint256 i=1; i<100; ++i) {
            NexoraEntryAllocationPreview.Allocation memory a = policy.preview(i);
            uint256 insider = a.ownerCharge + 10 * a.companyChargeEach;
            require(insider <= i / 5, "Excess charges");
            _eq(a.netPrincipal + insider, i);
        }
    }

    function testFuzz_NoMoneyCreatedByDepositFeeMath(uint96 raw) public view {
        uint256 gross = uint256(raw) + 1;
        NexoraEntryAllocationPreview.Allocation memory a = policy.preview(gross);
        _eq(a.netPrincipal + a.ownerCharge + 10 * a.companyChargeEach, gross);
        require(a.netPrincipal >= gross * 4 / 5, "Less than disclosed net principal");
        require(a.ownerCharge <= gross * 600 / 10_000, "Owner fee too high");
        require(a.companyChargeEach <= gross * 140 / 10_000, "Company fee too high");
    }

    function testZeroGrossRejected() public {
        bool failed;
        try policy.preview(0) returns (NexoraEntryAllocationPreview.Allocation memory) {} catch {
            failed = true;
        }
        require(failed, "Zero gross accepted");
    }
}
