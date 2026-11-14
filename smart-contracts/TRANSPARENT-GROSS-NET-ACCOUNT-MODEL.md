# Nexora account display: full GROSS deposit record, transparent NET principal

> **Historical design snapshot:** the separate `NexoraModel2Vault` now implements a testnet-only prototype. Earlier statements in this document that the model is preview-only apply to the older `NexoraProfitVault`. It remains unaudited, unverified on public testnet and unavailable for real deposits; see the current [README](./README.md).

**DRAFT — not deployed, not merged, not connected to any live financial account.**

## Latest requested interpretation

The owner selected **Model 2**: with each 1,000 USDT external deposit, allocate **6%** to the platform owner and **1.4% each** to ten company payout wallets. The remaining **80%** is retained as user-owned principal.

The owner also requests that the user's account still **record and show the entire 1,000 USDT they paid in**. The safe implementation is a *gross deposits ledger* of 1,000 USDT shown prominently, **not a fictitious 1,000 USDT protected/cashable current balance**.

### Required account view (1,000 USDT deposit)

| UI label | Value | Meaning |
| --- | ---: | --- |
| **Total deposited / جمع واریزی‌ها** | **1,000 USDT** | Actual original gross deposit, always recorded honestly as a historical transaction |
| Owner allocation (6%) | 60 USDT | Upfront deduction disclosed at payment confirmation |
| Ten corporate allocations (1.4% each) | 140 USDT | Upfront deduction, 14 USDT to each of ten company wallets |
| **Net capital / سرمایه خالص** | **800 USDT** | **Actual backed principal** that may eventually be withdrawn under agreed maturity/caps |
| Gross plan reference / مبنای پلن | **1,000 USDT** | An OPTIONAL reference for tier rates, **not a second liability or guaranteed principal** |
| Remaining principal currently available | 800 USDT before other withdrawals, locked 90 days | This must always use actual net-backed balance |
| Withdrawal fee | **0%** | No additional withdrawal fee |

### Reward calculation on 1,000 USDT

If the platform wishes to calculate the **conditional** VIP-1 reward ceiling using the 1,000 USDT gross plan reference, then that ceiling is **1% × 1,000 = 10 USDT/day**. This can be a cap only: no new profits arise from the deposit, and actual reward allocation is **zero unless funded from independently verified available business income**. A risk-controlled contract would need a *separate* gross-plan basis variable while recording *only 800* as principal debt. It must not label the gross 1,000 reference as redeemable or protected principal.

This **is not currently implemented**: the latest NexoraProfitVault prototype calculates rate ceilings on its `principal` field and retains 100% of deposits. Switching to an 80% net-deposit model requires a new independently audited integration with explicit upfront disclosure and consent. Merely changing the frontend number would be materially misleading.

### 20% every 24 hours

If the contractual daily cap is defined on the user's **gross external deposits** of 1,000 USDT, the nominal maximum is **200 USDT** for an anchored 24-hour period, after the 90-day lock. A withdrawal can **never exceed the remaining actual net principal and funded claimable rewards**. If the remaining redeemable principal is 800 USDT and no actual rewards are available, it cannot produce an additional 200 USDT beyond that balance. Four successful 200 USDT principal withdrawals on separate eligible days would exhaust the 800 USDT redeemable principal; **the historical 1,000 USDT deposited value remains visible, but does not indicate 1,000 USDT remains owed**.

No withdrawal fee is charged.

### Reinvest example

From **100 USDT of actually allocated and fully backed reward**, a user voluntarily reinvests the gross amount:

| Item | Amount |
| --- | ---: |
| Gross reinvest transaction (historical record) | 100 USDT |
| Owner allocation at 6% | 6 USDT |
| Ten corporate allocations at 1.4% each | 14 USDT total |
| New net locked principal | **80 USDT** |

The *historical* Reinvest of 100 USDT is recorded, but **only 80 USDT is newly backed principal**. If the business instead wants to credit **all** 100 as net principal, an extra 20 USDT from separate corporate funds would be necessary; this is Model 1, not Model 2.

### Mandatory UI safety and consent

A user's account may show **1,000 USDT total deposits** and, in the same view with equally clear labels, **800 USDT net principal**. It must never present 1,000 USDT as a fully backed withdrawable balance without an extra 200 USDT funding source.

Before each deposit or reinvest:
1. Show the exact gross amount, the permanent upfront allocation of 20% (6% + ten × 1.4%), the net principal, 90-day lock, 20%/24h limit and 0% withdrawal fee.
2. Require informed opt-in and make account receipts independently reviewable.
3. Track protected net principal on chain and enforce that contracts are solvent for real user claims.
4. Require true independent realized profit before any reward credit. Do not promise the advertised 1–2.5%/day tier ceilings as guaranteed returns.
5. Never use fresh participants' deposits to finance old participant rewards.

### Implementation and operational status

This branch contains **preview-only** pure math and account-view specifications. **No ERC20 transfers, deductions, payout routers, onchain account balances, or website displays have been modified.** The existing vault on this parent branch still uses the full-gross principal Model 1. Do NOT deploy or connect a real deposit interface until the accounting change, legal disclosures, independent review and BNB testnet tests have been finished.
