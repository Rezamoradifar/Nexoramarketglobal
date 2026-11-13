// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraEntryAllocationPreview
 * @notice NON-EXECUTING preview of disclosed Model 2: GROSS transaction
 *         visible in the account, but only NET paid-in capital is backed.
 *
 * This contract NEVER holds/transfers tokens. It is NOT implemented in
 * NexoraProfitVault or any live frontend. It cannot be used as an oracle
 * for guaranteed profit or the real account's available balance.
 *
 * On 1,000 USDT gross paid, the receipt must visibly show BOTH:
 *  - 1,000 USDT: historical GROSS amount deposited and plan reference
 *  -   800 USDT: NET actual principal remaining after 20% entry allocation
 * DO NOT label the 1,000 USDT as withdrawable or protected capital.
 */
contract NexoraEntryAllocationPreview {
    uint256 public constant DENOMINATOR = 10_000;
    uint256 public constant OWNER_BPS = 600;      // 6% of gross
    uint256 public constant COMPANY_BPS = 140;    // 1.4% per company
    uint256 public constant COMPANY_COUNT = 10;
    uint256 public constant WITHDRAWAL_FEE_BPS = 0;
    uint256 public constant DAILY_WITHDRAWAL_BPS = 2_000; // 20% of gross reference

    error ZeroAmount();

    struct AccountReceipt {
        uint256 grossAmountRecorded;
        uint256 planReferenceAmount;
        uint256 netPrincipalCredited;
        uint256 ownerAllocation;
        uint256 companyAllocationEach;
        uint256 companyAllocationTotal;
    }

    function preview(uint256 grossPaidOrFundedReinvest)
        public pure returns (AccountReceipt memory r)
    {
        if (grossPaidOrFundedReinvest == 0) revert ZeroAmount();
        r.grossAmountRecorded = grossPaidOrFundedReinvest;
        r.planReferenceAmount = grossPaidOrFundedReinvest;
        r.ownerAllocation = _floorBps(grossPaidOrFundedReinvest, OWNER_BPS);
        r.companyAllocationEach = _floorBps(grossPaidOrFundedReinvest, COMPANY_BPS);
        r.companyAllocationTotal = r.companyAllocationEach * COMPANY_COUNT;
        // Rounding dust is credited to user principal, not to insiders.
        r.netPrincipalCredited = grossPaidOrFundedReinvest
            - r.ownerAllocation - r.companyAllocationTotal;
    }

    /**
     * A proposed plan may refer to 100% of the historical deposit for its
     * daily cap. This reference is NOT user-owned principal and creates NO
     * automatic reward; credits require independent realized funding.
     */
    function previewConditionalRewardCeiling(
        uint256 grossReference,
        uint16 conditionalTierBps
    ) external pure returns (uint256) {
        return _floorBps(grossReference, conditionalTierBps);
    }

    /**
     * Only actual MATURED and BACKED capital or credited rewards can be
     * withdrawn. The nominal daily cap is 20% of the gross reference,
     * but never creates funds beyond the actual mature balance.
     */
    function previewWithdrawable(
        uint256 historicalGrossDeposits,
        uint256 alreadyPaidInCurrent24h,
        uint256 actualMatureBackedBalance
    ) external pure returns (
        uint256 dailyCap,
        uint256 remainingDailyAllowance,
        uint256 currentlyWithdrawable
    ) {
        dailyCap = historicalGrossDeposits / 5;
        remainingDailyAllowance = alreadyPaidInCurrent24h >= dailyCap
            ? 0 : dailyCap - alreadyPaidInCurrent24h;
        currentlyWithdrawable = actualMatureBackedBalance < remainingDailyAllowance
            ? actualMatureBackedBalance : remainingDailyAllowance;
    }

    function _floorBps(uint256 amount, uint256 bps) private pure returns (uint256) {
        return (amount / DENOMINATOR) * bps
            + (amount % DENOMINATOR) * bps / DENOMINATOR;
    }
}
