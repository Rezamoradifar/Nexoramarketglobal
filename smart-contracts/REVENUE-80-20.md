# Nexora revenue funding: separate 80% reserve / 6% owner / 14% companies

**Unaudited and not deployed. No real customer deposits or automatic payouts.**

**Two flows must be kept separate:**

## 1. Deposits / Reinvest: 100% credited principal

**1,000 USDT deposit → the user's protected principal and reward calculation basis are 1,000 USDT, all fully held in the vault.** Do not take 20% out of the user deposit while representing the full 1,000 USDT as backed principal.

If the platform offers company payouts equal to 6% to owner and 1.4% to each of ten company wallets **triggered by each deposit or Reinvest**, these payouts require **additional independent company funding**. For a 1,000 USDT deposit, 200 USDT must come from *outside* the deposit. Total token requirements = 1,000 for the user + 200 from the company. For a 100 USDT already-funded reward Reinvest, all 100 becomes new principal; company-funded bonuses require an extra 20 USDT. This deposit-linked payout mechanism is **not implemented** in the current router and must not be represented as live.

See [fully backed gross accounting](./GROSS-PRINCIPAL-SPONSORED-COMPANY-PAYOUTS.md) and the non-operative `NexoraEntryAllocationPreview.sol`.

## 2. Independently funded operator revenue routing

The existing `NexoraRevenueRouter.sol` only accepts independently funded business revenue and sends 80% to `NexoraProfitVault.fundRewards`, 20% to `NexoraRevenueSplitter`. The splitter claims are fixed by immutable code as **30% owner and 7% for each of ten company wallets of that 20% subpool**.

| Destination | Share of independent revenue | Example: 1,000 USDT independent revenue |
| --- | ---: | ---: |
| Reward reserve in NexoraProfitVault | 80% | 800 USDT |
| Owner wallet | 6% | 60 USDT |
| Ten distinct company wallets | 14% total (1.4% each) | 140 USDT (14 each) |
| **Total** | **100%** | **1,000 USDT** |

This is **not a per-deposit or per-reinvest trigger**. For deposit-linked company payouts, a separate funded and verifiable source must be established and its synchronization with audited deposit/reinvest events implemented later. No customer principal may be routed through these two contracts.

The router requires a unique evidence identifier to avoid duplicate routing. The identifier does **not** prove genuine trading or realized business profit. This system cannot independently prove financial performance or support guarantees.

## Security and deployment restrictions

- The source is prototype-only. No audited trading strategy, money-making automation, live deposit/withdraw, or Mainnet address exists.
- User principal must remain fully backed by on-chain tokens and never be distributed to operator or company wallet recipients.
- Independently confirm the company payout source, regulatory status, investor disclosures, multisig governance and treasury accounting before deployment.
- 0% withdrawal fee; 90-day separate principal-tranche maturity; cumulative 20% of external-deposit basis per anchored 24 hours of withdrawals, subject to unlocked balances.
- Conditional 1–2.5% daily rates are **maximums, not guaranteed**. Actual credited rewards require verified independently funded revenue and review.
- Mainnet remains blocked until independent audit, BNB testnet dress rehearsal, verified wallet addresses and legal signoff.
