# Nexora Profit Vault (v0.2 — TESTNET PROTOTYPE)

**NOT audited, NOT deployed, and NOT ready for investor funds.**

**Latest alternate proposal (Model 2):** [Transparent gross deposit / net principal account model](./TRANSPARENT-GROSS-NET-ACCOUNT-MODEL.md) is **preview-only**, and is NOT represented by the executable vault code on this branch. The owner wants `Total Deposited: 1,000 USDT` displayed while 6% is allocated to the owner and ten company wallets each receive 1.4%. The actual **user-owned net principal is then 800 USDT**, and both figures must be distinctly labeled. A 1,000 USDT plan reference amount cannot be advertised as a fully backed or redeemable balance. The vault still follows the *alternative* full-principal accounting until a separately audited and approved Model 2 implementation replaces it; **do not deploy**.

 It is deliberately separate from the live website and the legacy Polygon contract.

## Purpose and threat model

This contract holds principal as a liability to each individual depositor. Principal is not lendable or withdrawable by the administrator. A different, role-restricted wallet can **fund a rewards pool**, then a role-restricted allocator can credit fully backed amounts using an externally reviewable `reportId`. There is **no internal trading bot or proof of realized trading profits**. On-chain funding alone cannot establish that funds came from actual profitable trading.

The administrator can manage FUNDING, ALLOCATION and GUARDIAN roles, so it is a **trusted-operator system**, NOT fully decentralized. Only a public audit trail and independent controls on the operator's real strategy can substantiate claimed profits.

### Tier criteria (all on-chain; hypothetical daily caps, not guaranteed payouts)

| Tier | Personal capital | Active direct members | Eligible 3-level team volume | Max allocation per 24h |
| --- | ---: | ---: | ---: | ---: |
| VIP 01 | 10 USDT | 0 | 0 | 1% |
| VIP 02 | 500 USDT | 2 | 2,500 USDT | 1.25% |
| VIP 03 | 2,500 USDT | 4 | 12,500 USDT | 1.5% |
| VIP 04 | 10,000 USDT | 6 | 50,000 USDT | 2% |
| VIP 05 | 25,000 USDT | 10 | 125,000 USDT | 2.5% |

* Only personal deposits between 10 and 50,000 USDT are accepted.
* Any top-up resets the user's 24h maturity and any direct-member qualification already counted for them.
* To count as an active direct member, a direct referral must hold at least 100 USDT for 24h. Anyone may call `syncDirect(member)` to register eligibility. There is **no keeper built into the contract**.
* Volume means active principal of descendants at depths 1–3 (withdrawals reduce it immediately). The largest direct branch must account for **no more than 50%** of the volume for VIP 02–05. Each wallet can register at most 128 direct children to bound gas usage.
* Higher tiers use current on-chain conditions. Team volume is not separately 24h-matured; only personal balance and counted direct members are. A sybil-resistant identity policy and oracle may be needed before production.
* An authorized allocator may issue **at most one amount every 24h** to a member. That amount may be **zero**, and missed periods do not accrue automatically.
* Referrals receive **15%, 7%, and 3% of the credited base reward**, not of deposits. Only mature eligible referrers receive credits. Every actual credit is prepaid in the reward pool before accounting entries change.
* A fully qualifying 3-level chain requires a funded pool at least **125% of the member's credited base reward**.
* Users may withdraw their own principal and claim already-credit rewards even when paused.
* All contract math assumes a **fixed 18-decimal asset**. Fee-on-transfer/rebasing assets are NOT supported.
* No owner withdrawal, no upgradeable proxy, no token swapping, no funds sent to a trading bot.

## Build and test

Foundry (forge) and Node 22:

```bash
cd smart-contracts
npm install --no-audit --no-fund
forge build
forge test -vv
```

The repository's `contract-tests.yml` workflow checks compilation and tests independently.

## Network

**BNB Smart Chain testnet:** chain ID `97`, deploy only with your own newly deployed mock stablecoin to begin.

**BNB Smart Chain mainnet:** chain ID `56`, commonly used Binance-Peg BSC-USD/Binance-Peg USDT token is `0x55d398326f99059fF775485246999027B3197955`, **18 decimals**. It is **not native Ethereum USDT issued directly by Tether**. Independently verify address and token custody before deployment. No address for the vault has been deployed.

Constructor parameters:

```
NexoraProfitVault(
  address token,          // test token or independently verified BSC token
  address adminMultisig,  // multisig, not the deployer key
  address rewardsFunder,  // distinct wallet, non-user capital
  address rewardsAllocator
)
```

Only the **admin** has `DEFAULT_ADMIN_ROLE` (and can grant/revoke roles). The admin also initially has `GUARDIAN_ROLE`. `FUNDER_ROLE` and `ALLOCATOR_ROLE` are independent. Deploy with independent monitored keys and an externally published report policy.

## Must complete before any mainnet use

1. Independent Solidity security audit and adversarial/fuzz/property-based testing (especially 128-branch networks).
2. Legal/compliance review of marketing rates and financial licensing rules in each intended jurisdiction.
3. Public verifiable strategy accounting and an auditable source-of-funds system. **Funded pool != verified net profit.**
4. Independent multisig operational safeguards, time-delayed privileged changes, and backup/recovery planning.
5. Explicit custody/withdrawal policy, token depeg/rebase contingency, emergency drill, liquidity and gas-budget stress testing.
6. BNB testnet deployment, BscScan verification, canary deposit/withdraw tests, and real UI wallet binding only after approval.
7. Investor-facing text must state that caps are hypothetical and payouts depend on actual available realized profit; no guaranteed returns.

No investment contract has been deployed or enabled by committing this code.

## Final requested accounting: 100% gross user principal + independently sponsored company payouts

**See [Full gross-principal and company sponsor funding policy](./GROSS-PRINCIPAL-SPONSORED-COMPANY-PAYOUTS.md).**

- Depositing **1,000 USDT credits and retains all 1,000 USDT** as protected user principal and sets the reward tier's calculation basis to 1,000 USDT (subject to actual ongoing balance and eligibility).
- The owner requests **6% of the deposit reference amount** and ten corporate wallets **1.4% each**, when a deposit or fully funded reward reinvest occurs.
- These 20% company bonuses **cannot come out of depositor principal** if the system promises that the full gross user balance is protected. For a 1,000 USDT deposit, an **additional 200 USDT of independent company money** must fund 60 USDT owner and 14 USDT to each of ten companies.
- For 100 USDT of already funded rewards reinvested, all 100 USDT becomes new user principal. Any bonuses of 6 USDT for the owner and 1.4 USDT for each company require **another 20 USDT independently funded by the company**. No reward funds backing the user can be diverted.
- The **existing** `NexoraRevenueRouter.sol` has a fixed **80% independent revenue reserve / 20% recipient pool**; `NexoraRevenueSplitter.sol` splits that recipient pool **30% owner / 7% each of ten corporate wallets**, equivalent to 6% and 1.4% *of independently funded routed revenue*. **These are not automatically triggered by deposits or Reinvest.** That dedicated, verified, independently funded per-deposit subsidy linkage **has not yet been implemented**.
- The vault has **0% withdrawal fees**, a separate 90-day lock for principal tranches and a cumulative 20% per anchored 24-hour window withdrawal cap based on externally deposited amounts. The full principal is visible but it is not all immediately withdrawable.
- Daily tier rates 1–2.5% are **conditional maximums, never promised profits**. Credits require an authorized allocator and fully funded independent reward reserve; payouts can be zero.

There are 11 company/owner payout wallets, all unique and publicly verifiable. User principal is not under their control; no wallet can withdraw another member's principal. Administrative role governance remains a separate risk requiring multisig verification and independent audit.

## Mainnet preparation package (NOT a release)

A new **draft branch** carries the fail-closed BSC mainnet technical preparation:

- [Mainnet release checklist](./MAINNET-RELEASE-CHECKLIST.md) — all mandatory security, operational, testnet, legal and funding gates.
- [Atomic deployment factory](./src/NexoraSystemFactory.sol) — deploys the vault, splitter and router together and relinquishes temporary installer permissions.
- [Read-only mainnet technical preflight](./preflight-mainnet.sh) — validates chain ID 56, token contract and decimals, governance contract code, and beneficiary wallet uniqueness.
- [Read-only postdeployment verifier](./postdeploy-readonly.sh) — checks token/destination/role/solvency invariants after a *future independently authorized* deployment.
- [Environment example](./.env.example) — contains only blank public address fields, no private keys.

**These tools neither deploy nor prove a real investment strategy makes profits.** The smart-contract code is unaudited, the actual 11 beneficiary addresses and multisig admin are unknown, no live BNB testnet dress rehearsal is recorded, and the website does not yet have an independently verified wallet-integrated financial backend. Until every gate passes, keep financial operations OFF.

## Mainnet security stress test / current release decision (2026-11-14)

Latest [mainnet security test report](./MAINNET-TEST-REPORT-2026-11-14.md) and [CI evidence](https://github.com/Rezamoradifar/Nexoramarketglobal/actions/runs/43521333972): **84 Foundry tests passed**, including wider fuzzing (1,024 random cases per fuzz test), hostile-token rejection, funded accounting, 24-hour withdrawal boundaries, actual 11-wallet ratios, governance and **read-only market-feed freshness/role checks**. `forge coverage` and `npm audit --audit-level=high` run in CI. No vulnerabilities were reported by npm at that threshold, but main Solidity branch coverage is **42.86%–87.50%** and independent security audit is still required.

The `NexoraMarketOracleReader.sol` is only an independently configurable, **read-only** oracle interface; it neither places trades nor holds deposits. No live market feed is configured or independently verified.

**CRITICAL:** `NexoraProfitVault.deposit` still follows full-gross principal accounting, not the owner-approved Model 2 upfront 20% commission. Model 2 (historical gross amount vs real 80% net capital, 100% nonredeemable plan reference) is only a preview. The system is **not** integrated to the live site and has not been deployed to BSC Testnet or Mainnet. An automated [mainnet blocker report](./scripts/check-mainnet-blockers.py) documents **11 active release blockers** and can be run in fail-closed mode via `python3 scripts/check-mainnet-blockers.py --enforce`.

**Mainnet decision: BLOCKED. Do not turn on wallet transactions or receive investor funds.**
