// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraFullCreditPolicyPreview
 * @notice PURE MATH review contract. It moves NO tokens and is NOT deployed.
 *
 * The user requests that a 1,000-token deposit create exactly 1,000 tokens of
 * principal liability and that qualifying tier/conditional allocation caps
 * use the FULL 1,000, even while the owner and ten corporate wallets get
 * 10% and 1.4% each of the same gross reference amount.
 *
 * Both promises can be honored ONLY if the 24% is paid from a separate,
 * genuinely independent and fully-funded operator budget; NEVER subtract it
 * from customer deposits, the vault reward reserve backing prior credits,
 * or already-owed investor principal/rewards.
 */
contract NexoraFullCreditPolicyPreview {
    uint256 public constant DENOMINATOR = 10_000;
    uint256 public constant OWNER_BPS = 1_000;    // 10% of gross
    uint256 public constant CORPORATE_BPS = 140;  // 1.4% each of gross
    uint256 public constant CORPORATE_COUNT = 10;

    error ZeroAmount();
    error InsufficientIndependentSponsor();
    error InsufficientFundedReward();

    /**
     * @param gross Reference value: user's gross direct deposit or voluntary
     *        reinvestment of an actual already-credited, funded reward.
     * @param independentSponsorAvailable Operator capital available OUTSIDE
     *        vault principal, claimable rewards, and reward reserve.
     * @return creditedPrincipal Full 100% gross amount; NO entry fee from user.
     * @return ownerAward Amount sourced from independent operator capital.
     * @return eachCorporateAward Independent award per company wallet.
     * @return totalSponsorPayout Total independent capital required for payouts.
     *
     * This preview cannot verify the actual sponsor source. A production flow
     * must require external funding and prove all obligations are still backed
     * at every transfer. If funding fails, the entire payout request must revert.
     */
    function previewFullCredit(
        uint256 gross,
        uint256 independentSponsorAvailable
    ) external pure returns (
        uint256 creditedPrincipal,
        uint256 ownerAward,
        uint256 eachCorporateAward,
        uint256 totalSponsorPayout
    ) {
        if (gross == 0) revert ZeroAmount();
        ownerAward = _share(gross, OWNER_BPS);
        eachCorporateAward = _share(gross, CORPORATE_BPS);
        totalSponsorPayout = ownerAward + eachCorporateAward * CORPORATE_COUNT;
        if (independentSponsorAvailable < totalSponsorPayout) {
            revert InsufficientIndependentSponsor();
        }
        creditedPrincipal = gross;
    }

    /**
     * @notice Reinvest fully backed, already credited reward into a new
     *        principal tranche. Rewards liability decreases by "amount";
     *        principal liability increases by exactly the same "amount";
     *        independent sponsor cash is required for the corporate payouts.
     * @dev NO money moves in this math preview.
     */
    function previewReinvest(
        uint256 availableFundedRewards,
        uint256 amount,
        uint256 independentSponsorAvailable
    ) external pure returns (
        uint256 newPrincipal,
        uint256 remainingFundedRewards,
        uint256 ownerAward,
        uint256 eachCorporateAward,
        uint256 totalSponsorPayout
    ) {
        if (amount == 0) revert ZeroAmount();
        if (amount > availableFundedRewards) revert InsufficientFundedReward();
        ownerAward = _share(amount, OWNER_BPS);
        eachCorporateAward = _share(amount, CORPORATE_BPS);
        totalSponsorPayout = ownerAward + eachCorporateAward * CORPORATE_COUNT;
        if (independentSponsorAvailable < totalSponsorPayout) {
            revert InsufficientIndependentSponsor();
        }
        newPrincipal = amount;
        remainingFundedRewards = availableFundedRewards - amount;
    }

    function _share(uint256 amount, uint256 bps) private pure returns (uint256) {
        // Avoid uint256 overflow in multiplication for all input amounts.
        return (amount / DENOMINATOR) * bps +
            (amount % DENOMINATOR) * bps / DENOMINATOR;
    }
}
