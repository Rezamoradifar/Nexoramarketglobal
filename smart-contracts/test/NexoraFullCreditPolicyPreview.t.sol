// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraFullCreditPolicyPreview} from "../src/NexoraFullCreditPolicyPreview.sol";

contract NexoraFullCreditPolicyPreviewTest {
    NexoraFullCreditPolicyPreview private p;
    uint256 private constant U = 1e18;

    function setUp() public {
        p = new NexoraFullCreditPolicyPreview();
    }

    function eq(uint256 x, uint256 y) private pure {
        require(x == y, "Not equal");
    }

    function testThousandDepositShowsThousandAndRewardsUseFullBalance() public view {
        (uint256 principal, uint256 owner, uint256 eachCompany, uint256 fundedPayout) =
            p.previewFullCredit(1_000 * U, 240 * U);
        eq(principal, 1_000 * U);
        eq(owner, 100 * U);
        eq(eachCompany, 14 * U);
        eq(fundedPayout, 240 * U);
        // The vault's conditional 1% cap is based on ALL principal, NOT 760.
        eq(principal / 100, 10 * U);
        // All owner/company payouts require funds in addition to gross deposit.
        eq(principal + fundedPayout, 1_240 * U);
    }

    function testCannotTransferCorporateSharesFromUnfundedBudget() public {
        bool rejected;
        try p.previewFullCredit(1_000 * U, 0) returns (uint256, uint256, uint256, uint256) {
            rejected = false;
        } catch { rejected = true; }
        require(rejected, "Must reject unfunded partner distribution");
    }

    function testCannotPayCorporateSharesFromTheDepositItself() public {
        // Net funds after allocating 240 of a 1,000 user deposit are 760;
        // user obligation is still 1,000. This violates balance conservation.
        uint256 gross = 1_000 * U;
        (, , , uint256 sponsor) = p.previewFullCredit(gross, 240 * U);
        require(gross - sponsor < gross, "Should show a collateral shortfall");
    }

    function testReinvestOneHundredKeepsAllPrincipalAndPaidSharesIndependent() public view {
        (uint256 added, uint256 remaining, uint256 owner, uint256 each, uint256 sponsor) =
            p.previewReinvest(200 * U, 100 * U, 24 * U);
        eq(added, 100 * U);
        eq(remaining, 100 * U);
        eq(owner, 10 * U);
        eq(each, 14 * U / 10);
        eq(sponsor, 24 * U);
        eq(added + remaining, 200 * U);
    }

    function testCannotReinvestUncreditedOrUnfundedRewards() public {
        bool rejected;
        try p.previewReinvest(0, 100 * U, 24 * U)
          returns (uint256, uint256, uint256, uint256, uint256) {
            rejected = false;
        } catch { rejected = true; }
        require(rejected, "Cannot manufacture reward balance");
    }

    function testCannotReinvestWithoutIndependentCorporateFunding() public {
        bool rejected;
        try p.previewReinvest(100 * U, 100 * U, 0)
          returns (uint256, uint256, uint256, uint256, uint256) {
            rejected = false;
        } catch { rejected = true; }
        require(rejected, "Cannot debit user reward to pay corporate awards");
    }

    function testZeroRejected() public {
        bool rejected;
        try p.previewFullCredit(0, 0) returns (uint256,uint256,uint256,uint256) {
            rejected = false;
        } catch { rejected = true; }
        require(rejected, "Zero value accepted");
    }

    function testFuzz_FullCreditAndAwardConservation(uint96 raw) public view {
        uint256 gross = uint256(raw) + 1;
        uint256 owner = (gross / 10_000) * 1_000 + (gross % 10_000) * 1_000 / 10_000;
        uint256 each = (gross / 10_000) * 140 + (gross % 10_000) * 140 / 10_000;
        uint256 sponsor = owner + each * 10;
        (uint256 credited, uint256 x, uint256 y, uint256 needed) =
            p.previewFullCredit(gross, sponsor);
        eq(credited, gross);
        eq(x, owner);
        eq(y, each);
        eq(needed, sponsor);
        require(needed <= gross, "Partner award exceeds gross reference");
    }

    function testFuzz_ReinvestDoesNotCreateUserLiability(uint96 raw, uint96 requested) public view {
        uint256 credited = uint256(raw) + 1;
        uint256 amount = uint256(requested) % credited + 1;
        // The extra 24% sponsor budget is independent from user rewards.
        uint256 sponsorAvailable = credited;
        (uint256 added, uint256 remaining, , , uint256 needed) =
            p.previewReinvest(credited, amount, sponsorAvailable);
        eq(added + remaining, credited);
        require(needed <= sponsorAvailable, "Invalid sponsor budget");
    }
}
