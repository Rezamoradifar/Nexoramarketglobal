// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraEntryAllocationPreview
 * @notice READ-ONLY allocation mathematics for a proposed 20% entry/reinvest
 * fee. NOT A CUSTODY, DEPOSIT, REINVESTMENT OR PAYMENT CONTRACT.
 *
 * The user proposes applying the split to EACH user deposit and EACH
 * funded-reward reinvestment. 80% becomes newly credited NET user principal.
 * 6% is a platform owner charge; ten company wallets each get 1.4%.
 *
 * Previous contracts kept 100% of gross principal and had a separate
 * independently funded revenue router. Do NOT use those contracts for live
 * funds while this policy transition remains unsigned and unaudited.
 */
contract NexoraEntryAllocationPreview {
    uint256 public constant BPS = 10_000;
    uint256 public constant RETAINED_PRINCIPAL_BPS = 8_000;
    uint256 public constant OWNER_ENTRY_BPS = 600;
    uint256 public constant COMPANY_ENTRY_BPS = 140;
    uint256 public constant COMPANY_COUNT = 10;
    uint256 public constant WITHDRAWAL_FEE_BPS = 0;

    error InvalidAmount();

    struct Allocation {
        uint256 netPrincipal;
        uint256 ownerCharge;
        uint256 companyChargeEach;
        uint256 roundingToNetPrincipal;
    }

    /**
     * @dev Balance is conserved. Tiny rounding remainders stay in NET
     * principal rather than disproportionately compensating insiders.
     * No user tokens can be transferred or received by this contract.
     */
    function preview(uint256 grossDepositOrReinvest)
        external pure returns (Allocation memory a)
    {
        if (grossDepositOrReinvest == 0) revert InvalidAmount();
        a.ownerCharge = grossDepositOrReinvest / BPS * OWNER_ENTRY_BPS
            + (grossDepositOrReinvest % BPS) * OWNER_ENTRY_BPS / BPS;
        a.companyChargeEach = grossDepositOrReinvest / BPS * COMPANY_ENTRY_BPS
            + (grossDepositOrReinvest % BPS) * COMPANY_ENTRY_BPS / BPS;
        a.netPrincipal = grossDepositOrReinvest
            - a.ownerCharge - COMPANY_COUNT * a.companyChargeEach;
        uint256 floorNet = grossDepositOrReinvest / BPS * RETAINED_PRINCIPAL_BPS
            + (grossDepositOrReinvest % BPS) * RETAINED_PRINCIPAL_BPS / BPS;
        a.roundingToNetPrincipal = a.netPrincipal - floorNet;
    }

    /**
     * @notice Illustrative per-24h withdrawal cap applied to net credited
     * principal, not gross deposits. This is NOT stateful enforcement.
     */
    function previewDailyCap(uint256 netCreditedPrincipal)
        external pure returns (uint256)
    {
        return netCreditedPrincipal / 5;
    }
}
