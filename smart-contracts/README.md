# Nexora Profit Vault (v0.1 — TESTNET PROTOTYPE)

**NOT audited, NOT deployed, and NOT ready for investor funds.** It is deliberately separate from the live website and the legacy Polygon contract.

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

## Fixed 80/10/10 allocation: user-reward vault, owner, and ten partners

The **NexoraRevenueRouter.sol** transfers **80% of separately funded revenue** into the vault's independent reward reserve and **20%** into **NexoraRevenueSplitter.sol**. The splitter has exactly 11 recipients: owner wallet index 0 receives **50% of that 20% pool (= 10% of total funded revenue)**; 10 partners at indices 1–10 each receive **5% of the 20% pool (= 1% of total funded revenue each)**.

- Eleven public wallet addresses are constructor inputs. Every wallet must be unique and nonzero. Percentages are **fixed in the code**, not provided by the deployer: owner 5,000 BPS of splitter pool, each partner 500 BPS. The 11 weights sum to 10,000 BPS.
- **Approved distribution:** 80% of separately funded revenue remains as rewards in the smart-contract vault; 10% of total revenue goes to the owner, and each of ten partners receives 1% of total revenue. All tests enforce this allocation.
- The 100% splitter distribution means **100% of its own 20% sub-pool**, not user deposits, investor-reward credits, or necessarily all gross business revenue.
- No wallet receives any funds until an authorized funder transfers tokens into this contract for a specific, unique accounting evidence ID. The evidence ID is not proof of realized profit.
- Once funded, the contract records fully backed claimable balances. Each recipient claims its own share; even the admin cannot claim someone else's balance.
- Addresses are **immutable** after deployment and percentages are fixed in source code. Changes require revised code/new deployment and settlement of existing pending claims.
- Administrators can pause new funding, but beneficiaries can still claim existing shares. There is no sweep or arbitrary recipient-payout function.
- The splitter does **not** handle user deposits. Only an explicitly authorized router sends separately funded revenue (80% to the reward vault, 20% to this splitter). Neither contract proves trading profit or executes a strategy.

### Constructor parameters

```solidity
NexoraRevenueSplitter(
    address token,           // 18-decimal verified BEP-20 token
    address adminMultisig,   // governance and emergency pausing
    address fundingWallet,   // sole account permitted to fund distributions
    address[11] wallets      // index 0 = owner, indices 1..10 = partners
)
```

User wallets do not need private keys shared in chat. Only their public wallet addresses should be provided for the deployment parameters. An independent audit, published funding-account policy and legal review are mandatory before any real-money launch.

### Economics still to decide

The percentages are fixed: **80% vault / 10% owner / 1% for each of ten partners**. Before deploying, establish (a) the externally verified net distributable business revenue definition, (b) all 11 public payout addresses, (c) trustworthy multisig roles, and (d) any reserve retained **before** revenue enters this router. Never assume token funding proves realized profits.

## Mainnet preparation package (NOT a release)

A new **draft branch** carries the fail-closed BSC mainnet technical preparation:

- [Mainnet release checklist](./MAINNET-RELEASE-CHECKLIST.md) — all mandatory security, operational, testnet, legal and funding gates.
- [Atomic deployment factory](./src/NexoraSystemFactory.sol) — deploys the vault, splitter and router together and relinquishes temporary installer permissions.
- [Read-only mainnet technical preflight](./preflight-mainnet.sh) — validates chain ID 56, token contract and decimals, governance contract code, and beneficiary wallet uniqueness.
- [Read-only postdeployment verifier](./postdeploy-readonly.sh) — checks token/destination/role/solvency invariants after a *future independently authorized* deployment.
- [Environment example](./.env.example) — contains only blank public address fields, no private keys.

**These tools neither deploy nor prove a real investment strategy makes profits.** The smart-contract code is unaudited, the actual 11 beneficiary addresses and multisig admin are unknown, no live BNB testnet dress rehearsal is recorded, and the website does not yet have an independently verified wallet-integrated financial backend. Until every gate passes, keep financial operations OFF.
