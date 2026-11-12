# Nexora proposed 3-month withdrawal lock and 30% fee

**Status: TERMS REVIEW PENDING. This document is NOT implemented in Solidity, NOT deployed, and NOT approved for mainnet.**

## Statement from platform owner

> "اصل سود بعد سه ماه قابل برداشت با کارمزد ۳۰ درصد"

Working interpretation: the user wants **principal and allocated rewards** available for withdrawal **after three months**, with a **30% withdrawal fee**. However, the **fee basis** is still ambiguous and must be confirmed before code or contracts are changed.

The current vault code instead allows immediate user principal withdrawals and allows immediate withdrawal of already-allocated funded rewards. The new rule is a material change to user rights and requires explicit advance disclosure and prospective user consent. There are no funds/contracts live to migrate in this branch.

## One essential clarification

**Is the 30% fee assessed on the total withdrawn amount (principal + allocated reward), or only on allocated reward?**

These are materially different:

| Example after the lock expires | Fee on total withdrawal | Fee on reward only |
| --- | ---: | ---: |
| Principal | 1,000 USDT | 1,000 USDT |
| Credited, funded reward | 200 USDT | 200 USDT |
| Amount before fee | 1,200 USDT | 1,200 USDT |
| 30% fee | 360 USDT | 60 USDT |
| Paid to user | 840 USDT | 1,140 USDT |

If no reward is credited, a fee on the whole amount makes an initial 1,000 USDT principal withdrawal just 700 USDT after 90 days, while a reward-only fee returns the full 1,000 USDT principal. This must be clearly communicated before funding.

**The recipient/beneficiary of the 30% fee is also not specified**: it cannot silently be assigned to the owner, partners, or reward pool. Reserve accounting and fee withdrawals need separately documented legal/economic justification.

## New owner conditions: 20% withdrawal cap and Reinvest

The owner also specified: **"سقف برداشت ۲۰ درصد اکانت واریزی؛ ری اینوست دارد"**.

Current working rule: maximum gross withdrawal in an explicitly defined period = **20% of the eligible externally deposited capital basis**, net of gross amounts already withdrawn in that period. Repeated transactions must be **cumulatively tracked**, not allowed to evade the cap. Eligible, fully funded rewards may be optionally **reinvested** by the user into a separately dated principal tranche; the proposed accounting does not manufacture additional profit.

The cap period has **not** been specified, nor whether the basis includes reinvested amounts. The earlier 30% fee base and destination remain unresolved. **This must not be silently guessed or deployed into an immutable contract.**

See [WITHDRAWAL-CAP-REINVEST-PROPOSAL.md](./WITHDRAWAL-CAP-REINVEST-PROPOSAL.md) and the non-operative pure-math helper [NexoraWithdrawalPolicyPreview.sol](./src/NexoraWithdrawalPolicyPreview.sol).

## Preliminary time-lock specification (not yet coded)

- Default technical interpretation of "three months" is **90 x 24-hour periods**, measured on-chain; calendar-month semantics would need a different policy.
- Each distinct deposit/top-up should have its own maturity timestamp to avoid unfairly extending previously matured capital when the user adds funds. A single resettable lastDepositAt is not acceptable for a long lock.
- The funding and accounting of credited rewards must be tracked separately; determine whether rewards become withdrawable at the maturity of the underlying capital tranche or must mature 90 days after each credit.
- After maturity, withdrawals should be user-initiated and check that claimed amounts are fully backed by token balances; no reward should become an entitlement merely because time passes.
- Emitted events must report gross amount, fee base, fee amount, net amount and distribution destination.
- During an emergency pause, define an explicit, auditable withdrawal-rescue rule. Never allow an operator to unilaterally extend a matured balance's lock without separate advance authorization.
- The 80% independently funded reserve / 10% owner / 1% per partner revenue split remains **separate**. Nothing in this withdrawal rule authorizes distributing user principal or withdrawing protected liabilities.
- All prior tests asserting immediate principal withdrawal would need to be revised, with additional tests for maturity boundaries, per-tranche top-ups, early attempts, partial redemptions, rounding, safe claimability, double withdrawal, emergency behavior, and fee distribution.
- **Do not** change the currently deployed/public site, merge to main, broadcast a contract, or onboard users before the fee scope and rules have been explicitly agreed and legally reviewed.

## Release gating

No contract implementation or mainnet launch until these answers are recorded:
1. 30% fee charged on **whole withdrawal** or **reward only**?
2. 90 days exactly or calendar three months?
3. Does credited reward mature with the corresponding principal deposit, or 90 days after the reward credit?
4. Who receives 30% fees, and how do they interact with existing 80/10/1x10 revenue sharing?
5. Are early withdrawals impossible, or possible under an expressly disclosed exceptional policy?

These terms must not be guessed into irreversible smart-contract bytecode.
