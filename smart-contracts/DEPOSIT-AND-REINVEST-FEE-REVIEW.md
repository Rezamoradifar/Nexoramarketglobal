# Nexora policy change: 24% upfront allocation on deposits AND Reinvest (DRAFT)

**Not deployed. Not integrated into NexoraProfitVault. Not approved for real-money users.** This proposal supersedes the earlier assumption that 76/10/14 distributions come exclusively from independently funded business revenue.

## Owner's correction

The proposed split should be triggered **on every incoming participant deposit and on every voluntary reinvestment** (not only on realized operator income):

| Recipient / outcome | Share of GROSS deposit or reinvest | Example for 1,000 USDT |
| --- | ---: | ---: |
| Net amount credited as user principal inside the vault | **76%** | 760 USDT |
| Platform owner's payout allocation | **10%** | 100 USDT |
| Ten company payout wallets | **1.4% EACH, 14% total** | 14 USDT each |
| **Total** | **100%** | **1,000 USDT** |

For 100 USDT **already-funded, already-credited** rewards voluntarily reinvested, the suggested breakdown is 76 USDT credited as new locked principal, 10 USDT allocated to owner, 1.4 USDT per company wallet. This must never be applied to *unearned* or imaginary rewards.

## CRITICAL: capital protection and consent

This changes the economic model and conflicts with the previous user instruction that owner and company wallets have no access to user principal.

If 24% of each deposit is paid to the owner/companies, **only 76% of the gross deposit is backed in the vault as the user's principal**. Do NOT say "100% of deposits are protected", "100% of the initial principal is withdrawable", or market the 24% as realized trading profits. A statement about the owner/partners having no access to principal could be true ONLY of the remaining 76%-credited user balance after this fully disclosed upfront transfer, **not** of the original gross payment.

Any real implementation would need **explicit, informed consent before each deposit/reinvest**, a non-reversible 24% entry/reinvest fee clearly labeled to end users, upfront visibility of net principal, named legal recipients, fee dispute and cancellation rules, relevant legal approval and independent audit. Never allow a backend operator to withdraw an arbitrary amount from custody. All immutable share percentages and fee recipients must be public.

**No financial distributions should be made to investors from subsequent investors' deposits.** Any user reward must come from independent, verified actual net profit or other legitimately funded rewards, with no guaranteed 1%-2.5% daily return. Promises of full principal and daily guaranteed yields would be inaccurate.

## Withdrawal implications

Previously specified by owner:
- 90-day lock on initial principal and separate reinvest tranches.
- 20% withdrawal cap per 24-hour accounting window.
- **NO withdrawal fee** (distinct from the newly proposed entry/reinvest deduction).

The earlier withdrawal policy helper used "external deposited amount" as a provisional basis. Under this new policy that is **not an acceptable assumed denominator**. Example:

- Gross user deposit 1,000 USDT; net credited principal 760 USDT.
- **Recommended** cap basis: current, eligible net credited principal. At 760 USDT this means **152 USDT gross** maximum in the first eligible 24-hour period, subject to maturity and available principal/rewards.
- Using the gross 1,000 USDT as basis would show a nominal 200 USDT/day limit, despite only 760 USDT actually being principal-backed. The cap must never imply the other 240 USDT can be returned.
- Decide whether the 20% cap covers withdrawals of net principal only, credited reward only or both, how to calculate basis after withdrawals, and whether reinvested net amounts affect it. These must be published before financial launch.

## Solvency/accounting invariants required

1. Only net 76% credited to user principal; never record the full gross deposit as a user liability after paying the 24% to company/owner.
2. The 10 company wallets must each receive precisely 1.4% (subject to sub-token-unit rounding) and the owner 10% of **gross actual incoming tokens**; no direct administrator access to remaining principal.
3. For reinvest, consume ONLY actual fully-funded user reward liabilities and create net 76% new principal liabilities; 24% must be independently accounted as a fully disclosed user-authorized fee, not "generated profit".
4. A reinvest operation cannot create additional units of tokens or increase total liabilities beyond previously backed amounts. A user's 90-day maturity for already aged principal must not be reset by an unrelated reinvest.
5. A 20% per-day withdrawal limit must apply **cumulatively** and may never override available matured user liabilities.
6. No operator/admin backdoor withdrawal, undisclosed discretionary fee, or transfer from custody without the user's deposit/reinvest consent.
7. Real audit, legal review, protection of customer funds, and honest risk disclosures are mandatory before processing real assets.

## Current implementation status

The code on the parent feature branch still allocates **separately funded operator revenue**, not user deposits or reinvestments. Its ratio was adjusted to **76/10/14** in prototype but **NO automatic fees from principal are implemented**. Do NOT use the current economic accounting documentation unchanged to describe a live product.

The new `NexoraDepositFeePreview.sol` is **pure math only**, for stakeholders to review financial consequences; it neither transfers ERC20 tokens nor edits the vault, routes actual deposits, or changes the live website.

**Hold point:** No live financial flows should be enabled until independently audited/legally reviewed fee rules and transparent user consent exist.
