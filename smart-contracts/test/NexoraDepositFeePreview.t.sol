// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraDepositFeePreview} from "../src/NexoraDepositFeePreview.sol";

contract NexoraDepositFeePreviewTest {
    NexoraDepositFeePreview private previewPolicy;
    uint256 constant U = 1e18;

    function setUp() public {
        previewPolicy = new NexoraDepositFeePreview();
    }

    function _eq(uint256 a, uint256 b) private pure {
        require(a == b, "Not equal");
    }

    function testGrossDeposit1000MeansOnly760NetPrincipal() public view {
        (uint256 net, uint256 owner, uint256 oneCompany, uint256 companies) =
            previewPolicy.preview(1_000 * U);
        _eq(net, 760 * U);
        _eq(owner, 100 * U);
        _eq(oneCompany, 14 * U);
        _eq(companies, 140 * U);
        _eq(net + owner + companies, 1_000 * U);
    }

    function testFundedRewardReinvest100MeansOnly76NewPrincipal() public view {
        (uint256 net, uint256 owner, uint256 oneCompany, uint256 companies) =
            previewPolicy.preview(100 * U);
        _eq(net, 76 * U);
        _eq(owner, 10 * U);
        _eq(oneCompany, 14 * U / 10);
        _eq(companies, 14 * U);
        _eq(net + owner + companies, 100 * U);
    }

    function test20PercentWithdrawalCapMustUseNetDepositorPrincipal() public view {
        (uint256 net,,,) = previewPolicy.preview(1_000 * U);
        _eq(previewPolicy.preview20PercentWithdrawalAllowance(net), 152 * U);
        // A full-gross account figure would misleadingly suggest 200 USDT/day.
        _eq(previewPolicy.preview20PercentWithdrawalAllowance(1_000 * U), 200 * U);
    }

    function testTinyDepositsNeverRouteRoundingDustToOwner() public view {
        (uint256 net, uint256 owner, uint256 company, uint256 allCompanies) =
            previewPolicy.preview(1);
        _eq(net, 1);
        _eq(owner, 0);
        _eq(company, 0);
        _eq(allCompanies, 0);
    }

    function testZeroAmountIsRejected() public {
        bool reverted;
        try previewPolicy.preview(0) returns (uint256, uint256, uint256, uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
        require(reverted, "Zero must be rejected");
    }

    function testFuzz_AllUnitsAccountedForWithNoHiddenFee(uint256 amount) public view {
        if (amount == 0) return;
        (uint256 net, uint256 owner, uint256 oneCompany, uint256 allCompanies) =
            previewPolicy.preview(amount);
        _eq(owner + allCompanies + net, amount);
        _eq(allCompanies, oneCompany * 10);
        require(net >= amount / 2, "Excessive unexplained fee");
    }

    function testFuzz_CompanyWalletsAllSameRate(uint96 arbitrary) public view {
        uint256 gross = uint256(arbitrary) + 1;
        (, uint256 owner, uint256 each, uint256 allCompany) =
            previewPolicy.preview(gross);
        _eq(allCompany, each * 10);
        require(owner + allCompany <= gross, "Cannot overpay operator");
    }
}
