# Nexora — Full account credit with independently funded corporate allocations

**Review draft. Not deployed. No change to the live site or real financial transactions.**

## Owner's clarified requirement

A customer who deposits **1,000 USDT** must see **1,000 USDT credited in their personal account**, with conditional VIP level and **potential reward calculations based on that full 1,000 USDT** (not 760 USDT). The same applies to reinvesting already funded, credited rewards.

The prior proposal to pay **10% to owner + 1.4% to each of 10 company wallets** directly out of that deposit would create an immediate 24% principal shortfall. **This is prohibited by the solvency requirement.**

## Safe, fully backed alternative

| Source of funds | Allocation | Example for 1,000 USDT deposit |
| --- | --- | ---: |
| User-supplied principal | 100% recorded as user principal; 100% stays in the vault | 1,000 |
| Separate company-funded distribution budget | Owner gets 10% of deposit *reference amount* | 100 |
| Separate company-funded distribution budget | Each of ten corporate wallets gets 1.4% of deposit *reference amount* | 14 each |
| **Company's additional committed funding** | **24% of reference amount, separate from deposits and existing customer liabilities** | **240** |

**Total actual cash required to both fully back the user and pay the company wallets: 1,240 USDT**: 1,000 from the user's deposit, 240 from a legitimately independent and fully funded company budget. There is **no 24% debit from customer capital**.

For a **100 USDT reinvestment** of *already funded and credited* reward:
- Deduct 100 from that user's claimable reward liability and create 100 of new principal liability, using the same existing 100 tokens already held in vault.
- A separate 24 USDT must be funded by the company if the corresponding payouts are to be made (10 owner + 1.4 each company).
- User's total credited principal grows by **100**, not 76. No additional tokens, debt, or profit can be created by reinvestment.
- Reinvested funds have their own 90-day lock; external user deposits are tracked separately for the 20% daily withdrawal cap until its denominator is formally agreed.

## Rewards and disclosures

A conditional 1% daily **maximum** applied to 1,000 qualifying USDT produces a **10 USDT theoretical cap**, NOT a guaranteed daily payment. Actual credits require documented realized profit and pre-funded reward money (including eligible 3-level referral bonuses). Users must clearly see "Eligible principal: 1,000 USDT", "Funded rewards: ...", and "Available to withdraw: ..." as distinct figures.

For clarity the company payout of 24% is based on a customer's deposit/reinvest **reference amount**, but its **economic and on-chain funding source must be independent company capital or independently substantiated business revenue**. Do not mislabel principal-funded payouts as trading income.

## Blockchain implementation status

- The current V2 `NexoraProfitVault` already records **100% of direct external deposits** and `reinvestRewards` transfers **100% of funded reward liabilities into new principal tranches** without a fee. `tierBps` and `allocateReward` use recorded full personal principal, subject to the contractual eligibility rules.
- The existing `NexoraRevenueRouter` only accepts separately funded external revenue; it currently does **not** automatically distribute on each deposit/reinvest. Do **not** claim the combined workflow has been implemented or deployed.
- A proposed sponsor-funded event/trigger can be added **only** once there is an externally committed and independently auditable budget with an explicit fail-safe for absent funds; the company payouts must never use deposited principal or reward liabilities.
- `NexoraFullCreditPolicyPreview.sol` is a **pure calculator** for showing exact obligations and funding gaps. It does not transfer funds, enable withdrawals, or pay companies.
- If external sponsor funding cannot be provided, the deposit may be credited in full, but **no owner/company payout can occur as a consequence of that deposit**. Do not create unbacked payout entitlements, phantom yield, or disguised fees.

## No change to agreed withdrawal controls

In the existing V2 draft only: 90-day lock on independently dated capital tranches, cumulative 20% maximum per 24-hour anchored withdrawal window (based on externally deposited basis), **zero withdrawal fee**, user-initiated reinvest. The relationship of reinvested principal to the 20% cap basis must still be formally clarified and independently audited.

## Release restrictions

This remains a separate, unmerged branch. The earlier [upfront 24% fee review](../DEPOSIT-AND-REINVEST-FEE-REVIEW.md) documented the incompatible 76%-net-credit interpretation. **This full-credit request supersedes that interpretation**, but the lack of an actual company funding source means production deployment and automatic allocations are not authorized.

Before mainnet: verify all 11 receiving addresses, multisig roles, independently funded company budget, accurate external profit records, user consent, independent smart-contract security audit, economic/legal review, actual BNB testnet tests, and 100% collateral reserves. Never share private keys or seed phrases.
