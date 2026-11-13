# Nexora Mainnet Security and Test Report — 14 November 2026

> **Historical snapshot:** this report predates the separate Model 2 testnet vault and its later tests. Statements below about Model 2 being only a preview refer to the older `NexoraProfitVault`, not the newer `NexoraModel2Vault`. See the current [README](./README.md). The security and real-network blockers still require independent verification.

> **Outcome: UNIT/INTEGRATION TESTS PASS. FINANCIAL MAINNET RELEASE BLOCKED.**
>
> This is not an independent audit, a live BNB Testnet deployment, a real-USDT transaction test, a legal assessment or proof of profitability. Do **not** turn on deposits or claims.

## Executed checks

Test run: [Nexora Mainnet Readiness CI #43521333972](https://github.com/Rezamoradifar/Nexoramarketglobal/actions/runs/43521333972)  
Source commit: `f54f60fcd9fc0347efebe250a52226a5be6be6ef` (auditable tested snapshot before this report update)  
Automated harness: Foundry/Solidity, local Ethereum execution with mock tokens and beneficiary addresses; **1024 fuzz cases per fuzz test**.  
Result: **84 tests passed, 0 failures, 0 skipped across 10 suites**; source code compilation successful.

| Tested property | Result | Scope |
| --- | --- | --- |
| 11 recipient addresses nonzero, EIP-55 valid and pairwise unique | PASS | Public address check, **not** signature ownership |
| Owner share 6%, each of ten company wallets 1.4%, vault reward reserve 80% | PASS | **Independently funded revenue only** |
| Disallow owner's/company's arbitrary withdrawal of another user's principal | PASS | Tested contract functions and configured recipient wallets |
| Externally funded reward credits backed by a separate token reserve | PASS | Mock ERC20, onchain ledger invariants |
| Withdrawal limit shared by principal and claimed rewards; cumulative 20% per 24 hours | PASS | Existing prototype, not final Model 2 |
| 90-day principal maturity, separate reinvest tranches, zero withdrawal fee | PASS | Existing prototype, not audited |
| Accounting conservation across deposits, revenue routing, claims and reinvest | PASS | Integration sequences and fuzz |
| Reject fee-on-transfer tokens that would underfund deposits/revenue | PASS | Adversarial mock token tests |
| Reject 6-decimal assets at vault/splitter creation | PASS | Adversarial mock token test |
| Read-only market feed: stale, future, invalid and unanswered rounds rejected; unauthorized config/disable blocked | PASS | Mock AggregatorV3 adapter; **no real market feed connected** |
| Reject unauthorized revenue routing and duplicate evidence identifiers | PASS | Existing contract unit tests |
| One-transaction factory bootstrap and administrative role transfer | PASS | Simulated BSC chain IDs, **not** a deployed multisig |
| Distinguish gross 1000/net 800 Model 2 math from actual vault implementation | PASS (GAP EXPOSED) | **Math preview only; production integration missing** |

## Measured automated code coverage (NOT an audit)

CI also runs `forge coverage --report summary` using its coverage compiler settings, and `npm audit --omit=dev --audit-level=high` for dependency vulnerability scanning.

| Main Solidity module | Line coverage | Branch coverage |
| --- | ---: | ---: |
| Profit vault / principal & reward accounting | **91.67%** | **63.64%** |
| Revenue router | **95.24%** | **42.86%** |
| Revenue splitter | **94.12%** | **60.00%** |
| Factory / role bootstrap | **100%** | **83.33%** |
| Read-only market oracle adapter | **100%** | **87.50%** |

The market adapter's latest-round response now checks that `answeredInRound >= roundId`, in addition to positive prices, update timestamps, non-future data, freshness, nonzero market IDs, feed contract code, and admin-only configuration. All tests use a local mock feed; **no external Chainlink proxy or live market service was integrated**.

**Finding:** Branch coverage remains modest in the core router, splitter and profit vault. Their unexplored branches require adversarial tests, economic-model reconciliation, independent reviewer analysis, testnet gas/role testing and stronger property-based invariants before any financial deployment.

**Dependency scan:** npm reported **0 vulnerabilities at the configured threshold** in this run. That does not constitute a Solidity audit, a comprehensive SBOM, or financial security approval.

## Release-blocking findings

### CRITICAL 1 — Required Model 2 is not implemented in the actual vault

Current vault `deposit(1,000 USDT)` records **1,000 USDT user principal** and does **not** route 60 USDT to owner or 14 USDT each to ten companies. Reinvest also does not pay company fees. The user-selected Model 2 requires a clearly disclosed historical `gross deposited: 1,000`, **net principal: 800**, and an explicitly separate (non-redeemable) **plan reference: 1,000**. The current executable vault calculates rewards against its `principal` balance; it does not distinguish gross plan reference from net principal.

The existing 80/6/14 funding router is NOT a per-deposit fee mechanism and must not be depicted as one. **No bridge or live financial workflow should be activated until the new rule is implemented, audited and user-consented.** Misreporting a 1,000 backed principal when only 800 is retained would be materially misleading.

### CRITICAL 2 — No independent audit or real BNB Testnet deployment

The tests above execute locally with mock ERC20 contracts. There is **no verified Testnet contract address**, no real transfer/withdrawal transaction hash, no BscScan verified source and no independent audit sign-off. A tested source tree cannot be called mainnet-ready.

### CRITICAL 3 — Reward economics not independently substantiated

The 1%-2.5% **daily** tier rates are conditional upper bounds, not earnings guaranteed by a trading engine. The `ALLOCATOR_ROLE` submits accounting reports; the contract cannot verify real realized profit. Deposits from new users must not fund rewards to earlier users.

### HIGH 4 — Governance and business controls absent

The eleven candidate public recipient wallets have valid syntax/checksums but **not proven signatory control**. A real multisig admin, role-assignment policy, loss recovery process, KYC/AML / regulatory authorization, operational monitoring, source-of-funds proof and legal financial disclosure review are not complete. The factory's `code.length` check alone cannot prove Safe configuration or signers.

### HIGH 5 — Operational / liveness stress not certified

Per-deposit/reinvest withdrawal tranches grow with each top-up; historical tranche length is **not bounded**, so worst-case withdrawal gas and griefing limits should be audited. Referral volume/gas stress tests, oracle/RPC disruptions, token freezes/depeg behavior and UI wallet binding still need Testnet scenario verification.

### HIGH 6 — Market connectivity unverified

Read-only market-data APIs, failover/monitoring, price freshness labels and reconciliation to on-chain revenues are not independently validated. Connecting to a world market-data source does **not** prove a strategy has earned profits or grant authority to trade user funds.

## Current automation and fail-closed release gate

- `scripts/check-beneficiary-config.py`: validates public addresses and percentages; no RPC or key required.
- `scripts/check-mainnet-blockers.py`: reports **11 active blockers** in CI; `--enforce` exits nonzero to prevent a false mainnet-ready declaration.
- `preflight-mainnet.sh`: **read-only** chain-ID, token, wallet and multisig bytecode checks (requires real inputs to execute).
- `postdeploy-readonly.sh`: onchain ratio/role/solvency verification after an *independently approved future deployment*, not a transaction sender.
- No software here can verify true wallet control or complete a third-party security audit by itself.

## Required end-to-end sign-off before a production launch

1. **Finalize and integrate fully transparent Model 2 on a new audited testnet contract**: gross deposited 1,000, net backing 800, displayed reference 1,000 (not redeemable), 20% upfront allocations, reward/reinvest math, zero additional withdrawal fee, 90-day maturity and cumulative 20%-per-24h cap.
2. Obtain written recipient-role confirmations and **independently verified ownership signatures** from owner and all ten companies. Set up a real separately verified admin multisig, issuer-wallet permissions, timelock and key-recovery procedures.
3. Complete independent smart-contract audit and remediate all critical/high findings, including complex referral tree and tranche gas exhaustion.
4. Publish independent source-of-funds and financial model evidence confirming rewards derive from lawful, realized profit and are fully funded.
5. Deploy approved source on **BNB Testnet (chain ID 97)** with a mock asset; verify contracts in explorer and record signed canary deposit, delayed withdrawal, reward, Reinvest, company claim, and emergency drill transaction hashes.
6. Connect the correct primary website to testnet-only contracts; test wallet, approvals, balances, gross/net disclosure, withdrawal blocks, networks and failure UX on desktop/mobile.
7. Perform external legal and compliance review of the fee model, yield claims, custodial structure, marketing and jurisdictions.
8. Require **human mainnet release sign-off** matching an audited source commit, deployed bytecode, address registry and independently verified multisig. Use a controlled production canary and monitoring only after all gates pass.

**Release decision as of 2026-11-14:** `MAINNET_NOT_AUTHORIZED`.

No BNB/USDT has been moved, no real smart contracts have been deployed, and no production services have been modified during this review.
