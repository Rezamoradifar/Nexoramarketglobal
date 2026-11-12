// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraEntryAllocationPreview
 * @notice SOLVENT, READ-ONLY accounting proposal; NOT a fund-transfer contract.
 *
 * New policy:
 *  - Each 1,000 USDT deposit is credited as 1,000 USDT user principal,
 *    and the 1,000 USDT remains in the user vault.
 *  - The full 1,000 USDT, not a reduced 800 USDT, is the conditional
 *    daily reward calculation basis.
 *  - If the owner gets 6% and ten company wallets get 1.4% each
 *    whenever a user deposits or reinvests, that 20% MUST be supplied
 *    IN ADDITION to principal by independently sourced company funds.
 *  - NEVER take the 20% from user deposits or already-funded user rewards
 *    while still reporting 100% as backed user principal.
 *  - Withdrawal fees are zero. Previous 90d maturity/24h withdrawal cap
 *    are specified separately and do not change full principal custody.
 *
 * The real independent company-funding path and proof of source of funds
 * remain unimplemented, unaudited and unapproved for any mainnet funds.
 */
contract NexoraEntryAllocationPreview {
    uint256 public constant BPS = 10_000;
    uint256 public constant USER_PRINCIPAL_BPS = 10_000;
    uint256 public constant OWNER_BONUS_BPS = 600;
    uint256 public constant COMPANY_BONUS_BPS = 140;
    uint256 public constant COMPANY_COUNT = 10;
    uint256 public constant WITHDRAWAL_FEE_BPS = 0;
    uint256 public constant DAILY_WITHDRAWAL_CAP_BPS = 2_000;

    error InvalidAmount();

    struct Allocation {
        uint256 creditedUserPrincipal;
        uint256 rewardCalculationBasis;
        uint256 ownerBonusFromIndependentFunds;
        uint256 companyBonusEachFromIndependentFunds;
        uint256 sponsorFundsRequired;
        uint256 totalExternalTokensRequired;
    }

    /**
     * @dev Models a NEW gross deposit with a separately prefunded company
     * subsidy for payouts. No user funds are split, moved or transferred.
     * Tiny amounts are rounded down on bonuses, not on user principal.
     */
    function preview(uint256 grossDeposit)
        public pure returns (Allocation memory a)
    {
        if (grossDeposit == 0) revert InvalidAmount();
        a.creditedUserPrincipal = grossDeposit;
        a.rewardCalculationBasis = grossDeposit;
        a.ownerBonusFromIndependentFunds =
            _bpsFloor(grossDeposit, OWNER_BONUS_BPS);
        a.companyBonusEachFromIndependentFunds =
            _bpsFloor(grossDeposit, COMPANY_BONUS_BPS);
        a.sponsorFundsRequired = a.ownerBonusFromIndependentFunds
            + COMPANY_COUNT * a.companyBonusEachFromIndependentFunds;
        // New on-chain deposit retains 100% and corporate sponsor pays separately.
        a.totalExternalTokensRequired =
            grossDeposit + a.sponsorFundsRequired;
    }

    /**
     * @notice Already funded and credited reward may become 100% principal
     * on reinvest. Paying separate 6% + ten x 1.4% company bonuses
     * requires new sponsor funds; no portion of rewards is deducted.
     * The reward liability is converted to principal, not duplicated.
     */
    function previewReinvest(uint256 fundedCreditedReward)
        external pure returns (Allocation memory a)
    {
        a = preview(fundedCreditedReward);
        // Reinvested reward is already held inside the vault; hence the only
        // additional tokens needed are sponsor-funded bonuses.
        a.totalExternalTokensRequired = a.sponsorFundsRequired;
    }

    /**
     * 20% of external deposit basis per 24h is an independently enforced
     * withdrawal policy. A 1,000 USDT principal can support a 200 USDT
     * gross daily withdrawal cap, not 160 USDT.
     */
    function previewDailyCap(uint256 grossExternalDepositBasis)
        external pure returns (uint256)
    {
        return grossExternalDepositBasis / 5;
    }

    function _bpsFloor(uint256 amount, uint256 bps) private pure returns (uint256) {
        return amount / BPS * bps + (amount % BPS) * bps / BPS;
    }
}
