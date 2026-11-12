// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraDepositFeePreview
 * @notice Pure calculator for review of proposed, FULLY DISCLOSED upfront
 *         charges on both deposits and voluntary reward reinvestment.
 *
 * NOT integrated into NexoraProfitVault, NOT an ERC20 custodian, NO transfers,
 * NO reward generation, NO withdrawal implementation. DO NOT DEPLOY TO MAINNET.
 *
 * WARNING: A fee of 24% means only 76% of incoming capital is owned by the
 * depositor as net principal. It must never be advertised as 100% protected.
 * Payouts cannot be financed from subsequent customer deposits.
 */
contract NexoraDepositFeePreview {
    uint256 public constant DIVISOR = 10_000;
    uint256 public constant OWNER_BPS = 1_000;    // 10% gross
    uint256 public constant COMPANY_BPS = 140;    // 1.4% gross per wallet
    uint256 public constant COMPANY_COUNT = 10;

    error ZeroAmount();

    /**
     * @param grossDepositOrFundedReinvest Actual tokens paid/consumed by user.
     * @return netPrincipal Amount credited as depositor's new principal.
     * @return ownerAmount 10% explicit entry/reinvest fee to owner.
     * @return amountEachCompany 1.4% fee per each of ten company wallets.
     * @return allCompaniesAmount The summed 14% fee for ten company wallets.
     *
     * Rounding remainder is credited to the user (not silently to operator).
     */
    function preview(uint256 grossDepositOrFundedReinvest)
        public pure
        returns (
            uint256 netPrincipal,
            uint256 ownerAmount,
            uint256 amountEachCompany,
            uint256 allCompaniesAmount
        )
    {
        if (grossDepositOrFundedReinvest == 0) revert ZeroAmount();
        ownerAmount = _percentage(grossDepositOrFundedReinvest, OWNER_BPS);
        amountEachCompany = _percentage(grossDepositOrFundedReinvest, COMPANY_BPS);
        allCompaniesAmount = amountEachCompany * COMPANY_COUNT;
        netPrincipal = grossDepositOrFundedReinvest - ownerAmount - allCompaniesAmount;
    }

    /**
     * Helper to illustrate 20% per 24h limit after crediting a net principal
     * basis. This does not enforce a withdrawal lock, per-period accrual or fee.
     */
    function preview20PercentWithdrawalAllowance(uint256 eligibleNetPrincipal)
        external pure returns (uint256)
    {
        return eligibleNetPrincipal / 5;
    }

    function _percentage(uint256 amount, uint256 bps) private pure returns (uint256) {
        // Full uint256 safe, avoiding multiplication overflow.
        return (amount / DIVISOR) * bps + (amount % DIVISOR) * bps / DIVISOR;
    }
}
