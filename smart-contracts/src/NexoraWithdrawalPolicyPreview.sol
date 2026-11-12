// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraWithdrawalPolicyPreview
 * @notice PROPOSAL ONLY: 20% of external deposit basis per unspecified period.
 *
 * NO TOKEN CUSTODY, NO BALANCE UPDATES, NO AUTHENTICATION, NO INTEGRATION
 * WITH NEXORA'S VAULT. This contract supplies pure calculations for tests.
 *
 * The policy cannot be enforced until the owner defines the reset PERIOD,
 * the fee basis/destination and the treatment of reinvested profits.
 */
contract NexoraWithdrawalPolicyPreview {
    uint16 public constant WITHDRAWAL_CAP_BPS = 2_000; // 20.00%
    uint16 public constant BPS = 10_000;

    error InvalidReinvestAmount();

    /**
     * @notice Gross withdrawal capacity within a future, well-defined period.
     * @param eligibleExternalDeposits Eligible externally paid principal basis.
     * @param alreadyWithdrawnInPeriod Sum of gross withdrawals already paid
     * within the SAME period (verified with on-chain period tracking later).
     *
     * Reinvested profits are purposefully not included in this draft basis.
     * Passing the entire current balance here is NOT an acceptable substitute.
     * This function does not enforce anything: it is pure preview math.
     */
    function previewRemainingWithdrawalCap(
        uint256 eligibleExternalDeposits,
        uint256 alreadyWithdrawnInPeriod
    ) external pure returns (uint256 totalPeriodCap, uint256 remainingCap) {
        // 20% = exactly one fifth, avoiding overflows from multiplying first.
        totalPeriodCap = eligibleExternalDeposits / 5;
        remainingCap =
            alreadyWithdrawnInPeriod >= totalPeriodCap
                ? 0
                : totalPeriodCap - alreadyWithdrawnInPeriod;
    }

    /**
     * @notice Illustrates moving already funded reward liability to a new
     * separately dated principal tranche; DOES NOT perform that transfer.
     * Maturity, fee and whether new principal counts for a future cap
     * have not been settled and are NOT implemented.
     */
    function previewReinvest(
        uint256 fundedClaimableRewards,
        uint256 reinvestAmount
    ) external pure returns (uint256 rewardsRemaining, uint256 newLockedPrincipal) {
        if (reinvestAmount == 0 || reinvestAmount > fundedClaimableRewards) {
            revert InvalidReinvestAmount();
        }
        rewardsRemaining = fundedClaimableRewards - reinvestAmount;
        newLockedPrincipal = reinvestAmount;
    }
}
