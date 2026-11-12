// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraEntryAllocationPreview} from "../src/NexoraEntryAllocationPreview.sol";

/**
 * SOLVENT accounting previews. No code here routes any user deposit
 * to an owner or company wallet.
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

    function testOneThousandUserBalanceAndRewardBasisRemainOneThousand() public view {
        NexoraEntryAllocationPreview.Allocation memory a = policy.preview(1_000 * U);
        _eq(a.creditedUserPrincipal, 1_000 * U);
        _eq(a.rewardCalculationBasis, 1_000 * U);
        _eq(a.ownerBonusFromIndependentFunds, 60 * U);
        _eq(a.companyBonusEachFromIndependentFunds, 14 * U);
        _eq(a.sponsorFundsRequired, 200 * U);
        _eq(a.totalExternalTokensRequired, 1_200 * U);
        _eq(policy.previewDailyCap(1_000 * U), 200 * U);
        _eq(policy.WITHDRAWAL_FEE_BPS(), 0);
    }

    function testHundredRewardReinvestKeepsOneHundredAsNewPrincipal() public view {
        NexoraEntryAllocationPreview.Allocation memory a = policy.previewReinvest(100 * U);
        _eq(a.creditedUserPrincipal, 100 * U);
        _eq(a.rewardCalculationBasis, 100 * U);
        _eq(a.ownerBonusFromIndependentFunds, 6 * U);
        _eq(a.companyBonusEachFromIndependentFunds, 14 * U / 10);
        _eq(a.sponsorFundsRequired, 20 * U);
        _eq(a.totalExternalTokensRequired, 20 * U);
        // The 100 USDT moved from fully funded reward liability to principal,
        // while the corporate company independently funds the 20 USDT payouts.
    }

    function testNoBonusPaidOutOfUsersBacking() public view {
        for (uint256 gross = 1; gross < 150; ++gross) {
            NexoraEntryAllocationPreview.Allocation memory a = policy.preview(gross);
            _eq(a.creditedUserPrincipal, gross);
            _eq(a.rewardCalculationBasis, gross);
            _eq(a.totalExternalTokensRequired - a.sponsorFundsRequired, gross);
            require(a.sponsorFundsRequired <= gross / 5, "Excess company bonus");
        }
    }

    function testFuzz_PrincipalNeverDilutedAndAllFundingMustBeCovered(uint96 raw) public view {
        uint256 gross = uint256(raw) + 1;
        NexoraEntryAllocationPreview.Allocation memory a = policy.preview(gross);
        _eq(a.creditedUserPrincipal, gross);
        _eq(a.rewardCalculationBasis, gross);
        _eq(a.totalExternalTokensRequired, gross + a.sponsorFundsRequired);
        _eq(a.sponsorFundsRequired,
            a.ownerBonusFromIndependentFunds + 10 * a.companyBonusEachFromIndependentFunds);
        require(a.sponsorFundsRequired <= gross / 5, "Over 20 percent");
        require(a.ownerBonusFromIndependentFunds <= gross * 600 / 10_000, "Owner over cap");
        require(a.companyBonusEachFromIndependentFunds <= gross * 140 / 10_000, "Company over cap");
    }

    function testFuzz_AlreadyFundedReinvestRequiresOnlySeparateCorporateSubsidy(uint96 raw) public view {
        uint256 reward = uint256(raw) + 1;
        NexoraEntryAllocationPreview.Allocation memory a = policy.previewReinvest(reward);
        _eq(a.creditedUserPrincipal, reward);
        _eq(a.totalExternalTokensRequired, a.sponsorFundsRequired);
        _eq(a.rewardCalculationBasis, reward);
    }

    function testNoZeroGross() public {
        bool failed;
        try policy.preview(0) returns (NexoraEntryAllocationPreview.Allocation memory) {} catch {
            failed = true;
        }
        require(failed, "Zero amount accepted");
    }
}
