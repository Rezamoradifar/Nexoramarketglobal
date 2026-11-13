# Nexora Mainnet Release Gate — BNB Chain (56)

> **Historical alternative-model checklist:** the 100%-backed sponsored-principal specification below is not the current Model 2 testnet prototype. Do not use this document as the final Model 2 terms. See the current [README](./README.md); all production audit, testnet, governance and funding gates remain open.

> **Status: BLOCKED FOR MAINNET.** This repository contains an unaudited prototype. Do not deploy with live investor funds, enable deposits, or publish unverified guarantees. The purpose of this branch is to prepare verifiable artifacts for the eventual release.

## Immutable release specification

| Item | Requirement |
| --- | --- |
| Network | BNB Smart Chain Mainnet — chain ID **56**, not testnet chain ID 97 |
| Token | Binance-Peg USDT (BSC-USD), `0x55d398326f99059fF775485246999027B3197955`, **18 decimals**; not Tether-native Ethereum USDT |
| Principal custody | **100%** of each user's deposit is retained as backed principal and is the conditional reward basis; withdrawals obey a disclosed 90-day tranche maturity and 20%/24h cap, with 0% fee |
| Distributable revenue | Only independent, documented, actually funded operator revenue may enter the router |
| Independently funded business revenue split | **80%** reward-reserve vault, **6%** owner, **1.4% each** of ten company wallets |
| Reward model | Only pre-funded allocations, maximum conditional **1%–2.5%** per day, no promised/guaranteed returns |
| Referral model | Pre-funded 15% / 7% / 3% of a credited base reward, **never of deposits** |
| Contracts | `NexoraProfitVault`, `NexoraRevenueSplitter`, `NexoraRevenueRouter`; deployed atomically via `NexoraSystemFactory` |
| Wallet addresses | Exactly 11 unique public payout addresses + independent admin multisig, revenue funder and reward allocator |
| Deployer | Prefer a hardware-backed wallet. NEVER store keys/seed phrases in GitHub, frontend, server or chat |
| Governance | A deployed, independently verified **multisig** with published owners and approval threshold; timelock strongly recommended |

## Latest deposit/Reinvest accounting — DO NOT treat company shares as deductions from full user principal

See [gross user principal / sponsor-funded bonuses](./GROSS-PRINCIPAL-SPONSORED-COMPANY-PAYOUTS.md). A user deposit of **1,000 USDT** is credited as **1,000 USDT fully backed principal**, and the eligible tier's reward cap uses the same **1,000 USDT**. The owner may receive **60 USDT** and each of ten company wallets **14 USDT** *only if independently sourced company funding supplies an extra 200 USDT*. It is misleading and financially insolvent to deduct that 200 USDT from the user deposit while telling the customer all 1,000 USDT remain protected.

Already-funded user rewards reinvest at their **full amount**, with no reduction in the user's backed principal. A separate company bonus subsidy must be supplied before any company payouts are made for reinvest events. **No automatic deposit/Reinvest commission source contract has been audited or integrated.** No deposits may be enabled until on-chain resources and liabilities reconcile.

## Gates: ALL must pass before any mainnet deployment

- [x] Independently funded revenue splitter fixes 80% reserve / 6% owner / 1.4% for each of 10 company wallets, independently of user principal.
- [x] Mainnet chain-ID and token-address gates in the factory.
- [x] Atomic bootstrap of vault, splitter, router, and handoff to a distinct admin governance address.
- [x] Read-only technical preflight tool that checks chain ID, token decimals, and public address uniqueness.
- [x] Foundry compilation and unit/fuzz tests run in CI.
- [ ] **Independent third-party security audit of all four contracts** and closure of critical/high findings.
- [ ] **Formal analysis/property-based invariants** under hostile tokens, max referral fan-out, long-lived trees, rounding, pauses, and gas limits.
- [ ] **BNB testnet (chain ID 97) deployment** of all four contracts, public explorer verification, and deposit/withdraw/referral/revenue-routing canary transactions.
- [ ] **11 public beneficiary addresses**: one owner plus ten partner wallets, with signed partner agreements. No placeholder or invented addresses.
- [ ] Independently deployed and verified **multisig admin**, documented signers, approval threshold, and incident response.
- [ ] Governance/timelock policy for role grants, revocations and allocator selection; no single party can silently redefine payouts.
- [ ] Independent revenue **source-of-funds and realized-profit** accounting, public reporting and a ban on using deposits or reinvested user rewards to fund owner/company bonuses.
- [ ] **Deposit/Reinvest-linked company bonus mechanism** that transfers 6%/1.4% exclusively from an extra 20% of genuinely independent company funds; the present router is NOT a deposit trigger and cannot be presented as one.
- [ ] Legal/regulatory review covering investor disclosures, marketing claims, USDT custody, KYC/AML, jurisdictional restrictions and operator revenue sharing.
- [ ] Operational scenario tests: USDT adverse behavior, RPC outage, pause and recovery, frontend mismatch, disaster recovery and monitoring.
- [ ] UI domain/SSL verification and **one authoritative site**, preserving existing design. Until then wallet connection, deposits and claims stay off.
- [ ] External monitoring and incident alerts for deposits, reward allocations, permissions changes, solvency and treasury balances.
- [ ] Deployment record with committed source SHA, compiler version, deploy tx hash, verified contract addresses, BscScan proofs and sign-off.

## Read-only mainnet infrastructure preflight

The preflight performs **no transactions**. It does not certify audits, economic profitability, legal compliance or true multisig ownership.

Use a **trusted private RPC URL locally**. A URL may contain an API token: do not paste it into chats or commits. Export only public wallet addresses. Example:

```bash
cd smart-contracts
# Install Foundry first and configure the approved RPC and addresses in
# your local shell or approved secret manager; do not commit filled-in values.
export MAINNET_RPC_URL="https://<your-mainnet-bsc-rpc>"
export NEXORA_ADMIN_MULTISIG="0x<verified-multisig>"
export NEXORA_REVENUE_FUNDER="0x<separate-funding-wallet>"
export NEXORA_REWARD_ALLOCATOR="0x<separate-allocator-wallet>"
export NEXORA_OWNER_WALLET="0x<owner-payout-wallet>"
export NEXORA_PARTNER_01="0x<partner-01>"
# ... continue through NEXORA_PARTNER_10

bash preflight-mainnet.sh
```

Expected success marker: `NEXORA_MAINNET_TECHNICAL_PREFLIGHT_OK__NO_DEPLOYMENT`.

If any chain, token, address, uniqueness, or admin-contract check fails, the script stops. This is deliberately not a deploy command.

## Atomic deployment factory

`NexoraSystemFactory` deploys vault/splitter/router in one transaction and performs temporary role bootstrap. When constructor completes:

- Only the configured router has routine funding privileges on the vault and splitter.
- The designated multisig/governance admin controls role administration and emergency pause.
- The temporary factory address relinquishes all its admin, guardian and funder roles.
- Revenue funder and rewards allocator are distinct.
- The splitter hardcodes percentages; only the 11 recipient addresses are constructor arguments.
- On **mainnet only**, the factory requires BSC chain ID 56, exactly the pinned Binance-Peg USDT token and an admin address with deployed contract code.

**Important:** `code.length > 0` does **not** prove an address is a genuine multisig, its signature threshold is adequate, or its owners are trusted; verify that separately.

Mainnet deployment is deliberately NOT automated in this branch. A manual signed deployment, approved bytecode and a published BscScan verification report are required after independent audit sign-off. No private-key examples are provided.

### Postdeployment verification (READ ONLY)

After an independently approved mainnet deployment, document the factory transaction hash and address. Export `NEXORA_FACTORY_ADDRESS` along with the same BSC RPC URL and public beneficiary addresses used in the preflight. Run:

```bash
cd smart-contracts
export NEXORA_FACTORY_ADDRESS="0x<deployed-factory-address>"
bash postdeploy-readonly.sh
```

This verifies that the factory's vault, splitter and router agree on the token and addresses; that independently funded payout ratios are 80/6/1.4x10; that the multisig owns vault/splitter administration; that routine funding is delegated to the router; that the factory no longer controls them; and that recorded liabilities are backed by token balances. It **cannot** verify all historic role grants, independent audits, strategy profits, token-issuer risks, multisig signers, or jurisdiction-specific compliance. Success means `NEXORA_POSTDEPLOY_READONLY_OK`, **not** approval to onboard investors.

## Known design and compliance limitations

- No trading bot or trustless proof of financial profit exists. Allocator reports are not an oracle that independently proves the earnings.
- The admin can still grant roles and change operational permissions; it is a **trusted-operator model**. A timelock, governance controls and public disclosures are needed.
- Report IDs avoid accidental duplicate funding but cannot prove source of funds.
- Referral networks do not inherently prove unique human identities. Anti-sybil controls and KYC are outside the Solidity prototypes.
- A 1%–2.5% *daily* ceiling is an unusually high annualized rate. The business must avoid misleading claims and must demonstrate that ordinary payouts cannot depend on new deposits.
- Fee-on-transfer, rebasing or otherwise nonstandard tokens are unsupported; stablecoins can freeze, depeg or change implementation.
- The 80% pool is an unallocated reward reserve, **not additional depositor principal and not automatic owed yield**.
- The existing ChatGPT Sites presentation and the React VPS deployment are distinct. Do not mistake visual changes or a successful frontend build for a live protocol release.

## Launch decision

Release authorization is not established until the remaining gates are independently verified and documented. No wallet transaction should be enabled for end-users before then.
