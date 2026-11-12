# Nexora: withdrawal cap and reinvest (review draft)

**Status: SOURCE-ONLY PROPOSAL. Not yet integrated into the vault. Not deployed. No current user withdrawal rights have changed.**

## Newly specified conditions

- Withdrawals are capped at **20% of the user's deposited account basis per period**.
- Users can **reinvest** their actually credited, fully funded reward.
- Earlier proposed conditions remain under review: **3-month maturity** and **30% withdrawal fee**.

### 20% example

If a user's qualifying externally deposited basis is 1,000 USDT, their withdrawal allowance for one period is **200 USDT gross**, less any amounts already withdrawn in that same period. For example, after withdrawing 120 USDT, only 80 USDT remains available **during that period**.

**Essential missing detail:** the owner has not specified the period. Without daily, weekly, monthly or fixed-per-contract definitions, separate transactions could bypass an intended withdrawal limit. Therefore the live vault has NOT been modified to enforce a reset rule.

The "basis" is also provisionally interpreted as **externally deposited principal currently eligible for withdrawal**, not projected returns or unearned interest. It does **not automatically include reinvested rewards**; otherwise the 20% withdrawal allowance could expand each time rewards are reinvested. This basis needs explicit agreement prior to vault integration.

### Reinvest behavior (proposal)

1. Only **reward already credited and backed by the reward reserve** can be reinvested. Estimates, projected APY or unlocked principal do not qualify as reward.
2. The user alone initiates the reinvest transaction; the admin has no power to force a reinvest.
3. Reinvest transfers credited reward from a separate reward liability to a new internal principal tranche, keeping full token backing. It must NOT mint earnings, transfer reward funds to the owner, or route anything through the 80/10/1x10 revenue split.
4. The reinvest tranche should carry its own three-month maturity, so a new reinvest cannot lock unrelated mature deposits.
5. An optional minimum reinvest amount, whether reinvested principal adds to the 20% cap basis, and whether new reinvest tranches count toward VIP/active-direct status are STILL UNDECIDED.
6. Reinvested rewards should never be counted twice in available reward and principal. Solvency and aggregate accounting invariants must be tested.

### Three-month hold and 30% withdrawal fee

The owner has asked for a three-month hold and a 30% fee, but **has not confirmed whether the 30% applies to the full gross withdrawal (principal + profit) or to only the realized and credited profit**, nor the fee destination. The vault currently permits immediate principal withdrawal and immediate claims. Neither three-month locking nor the fee has been merged into Solidity; do not represent them as live features.

### Required invariants for an audited implementation

- Cap must be enforced with **cumulative withdrawals in a clearly defined period**, not merely per transaction.
- Gross versus net cap application must be specified (if gross amount is capped at 20%, the 30% fee is deducted within that withdrawal).
- Withdrawals cannot exceed unlocked, backed principal or rewards, even when cap has remaining allowance.
- Overdue locks cannot be extended unilaterally by an operator.
- Deposits and reinvestments create independently dated tranches; mature balances cannot be relocked by unrelated top-ups.
- Reward-to-principal reinvestment changes internal liabilities only and never makes total assets or total user entitlement increase.
- Emergency pause handling, rate changes, and legacy account migration require separately disclosed terms.
- Users must see all amounts, timings, limits and fees **before** depositing, and confirm consent.

## Planned code

A separate pure-math helper `NexoraWithdrawalPolicyPreview.sol` is used to test 20% cap calculations and reinvest accounting examples. **It is not wired to production withdrawals** and does not alter user balances.

### Decisions needed before vault implementation

1. Cap reset: **every 24 hours, 7 days, 30 days, 90 days, or only once over the account lifetime?**
2. Is the cap based on eligible deposited principal balance, lifetime total external deposits, or deposits plus reinvested rewards?
3. Does the 30% fee apply to gross withdrawals or profit only, and who receives it?
4. Do reinvested rewards start a new 90-day lock, or inherit the original deposit's schedule?
5. Which balance can be withdrawn within the 20% cap: principal, profit, or the combined total?

Until these terms and independent audit/review are complete, do not deploy this policy or market it as an active investment feature.
