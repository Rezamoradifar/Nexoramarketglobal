# Nexora — Revised 90-day lock, 20% per 24h withdrawals and full-amount Reinvest

**Status: UNAUDITED FEATURE BRANCH / NOT DEPLOYED.** This replaces the earlier conflicting 30% withdrawal-fee and unspecified-period draft.

- **User gross deposit is 100% principal**, not an 80% net amount. A deposit of 1,000 USDT is recorded as 1,000 USDT of backed user principal.
- **Reward calculation uses currently credited principal** (1,000 USDT in that example, until withdrawals or additional funded reinvestments change it). Daily 1–2.5% rates are ceilings, not guaranteed yields.
- **90-day time lock:** each externally paid deposit and each Reinvest creates its own tranche with a 90-day unlock date. A later top-up does not relock an earlier deposit.
- **Withdrawal fee is exactly 0%.**
- **Withdrawal cap:** total gross withdrawals and already-funded reward claims, together, are bounded by 20% of the user's lifetime external-deposit basis per anchored 24-hour period. Example: 1,000 USDT deposited → at most 200 USDT gross in the same 24-hour window, provided it is matured and fully backed. This is not an unconditional entitlement.
- **Reinvest:** only previously allocated and already-backed rewards can become 100% new principal; e.g. 100 USDT credited funded rewards → 100 USDT new principal. It never manufactures additional token balances.
- Reinvest does not silently expand the *external deposit basis* determining the withdrawal cap, though it increases eligible principal for conditional reward rates and creates its own 90-day tranche.
- **6% owner and 1.4% per company wallet linked to a deposit or Reinvest require a separate 20% budget of independent company funds**. No payout from user principal is permitted when the account claims 100% backed principal.
- On-chain reward allocations depend on independent real funding; credited rewards do not exist merely because time passes.

**Important:** The vault prototype has per-tranche maturity, 20%-per-24h cap and fee-free withdrawals in source code. Neither independent company-funding automation nor a verified live frontend/wallet connection is implemented yet. Mainnet is blocked pending audit and actual token, treasury, legal and governance verification.

Read [gross-principal company-funding requirements](./GROSS-PRINCIPAL-SPONSORED-COMPANY-PAYOUTS.md).
