# Nexora Model 2 — Deep validation and remediation

**Date:** 2026-11-14  
**Decision:** LOCAL VALIDATION PASSED; PUBLIC TESTNET / MAINNET NOT RELEASED.  
**This is an engineering test report, NOT an independent security audit, proof of economic profit, investment recommendation, or deployment approval.**

## Evidence and scope

Repository: `Rezamoradifar/Nexoramarketglobal`  
Branch: `feature/nexora-model2-deep-validation-20261114`  
Starting source: `c25047fc0b78cec2368e59bbfc3167e051858c96`  
Validated code/test snapshot: `0fb9ceed68d3aecd6104d3df2099fa000c0d6839`  
[Successful full run](https://github.com/Rezamoradifar/Nexoramarketglobal/actions/runs/43605373114), job `132478763327`.  
[Initial reproduction run](https://github.com/Rezamoradifar/Nexoramarketglobal/actions/runs/43604836489), job `132477133206`.

All token balances, accounts, time advancement and signatures in these tests are simulated inside Foundry. No actual BNB Testnet or BNB Mainnet deposit, withdrawal, wallet approval, contract deployment or investor payment was broadcast. Existing live site and default Git branch were not changed.

## Results

- **128 tests passed, zero failed, zero skipped, 15 suites.**
- **44 test functions concern executable Model 2 / its deployment / its attack boundaries:** 13 pre-existing Model2 tests, 21 deep regression tests, 4 rolling-window tests, 5 hostile-token/callback tests and 1 randomized stateful-sequence test. The other 84 tests are legacy/shared-module regressions. Do not market all 128 as 128 independent Model2 security properties.
- Fuzz tests ran **1,024 generated inputs per fuzz test**. Coverage runs repeat with Foundry's separate coverage settings and 256 fuzz inputs.
- The stateful test includes 48 candidate operations per generated scenario (49,152 candidate slots across 1,024 scenarios), with preconditions and a mandatory successful deposit/reward/reinvest/withdraw/claim spine. Some randomized slots intentionally skip inapplicable operations; these are NOT 49,152 public-chain transactions.
- A separate rolling-cap differential fuzz test checks the checkpoint implementation against an independently maintained linear payment history over 64 time advances per generated scenario.
- Exact user-supplied 11 beneficiary addresses passed checksum, nonzero, uniqueness and allocation checks. Ownership/control signatures are still not established.
- `npm audit --omit=dev --audit-level=high` reported **0 vulnerabilities** in the dependency scan. This does not audit Solidity or economic behavior.

### Coverage of the actual Model2 contract

| Module | Lines | Statements | Branches | Functions |
| --- | ---: | ---: | ---: | ---: |
| `NexoraModel2Vault` | **99.62% (263/264)** | **98.30% (405/412)** | **90.24% (74/82)** | **100% (30/30)** |
| Model2 Testnet factory | 100% | 100% | 100% | 100% |
| Shared company splitter | 96.08% | 94.59% | 60% | 100% |
| Read-only market oracle | 100% | 97.50% | 87.50% | 100% |
| No-value test token | 100% | 100% | Not applicable | 100% |

Previous Model2 measured coverage was 61.92% of lines / 27.14% of branches. Coverage is a testing metric, **not an independent security rating or proof that all failure modes were found**. Shared/legacy contracts have their own lower-coverage areas and must not be silently treated as equally covered.

## Reproduced withdrawal-policy defect and correction

### Finding M2-01: fixed-window reset did not implement a rolling 24-hour limit

At a 1,000-USDT external deposit reference, the nominal 20% cap is 200 USDT. The original code allowed:

1. A one-smallest-unit withdrawal to start an anchored window.
2. At 23:59:59 after that first withdrawal, the remaining `200 USDT - 1 unit`.
3. One second later, after the anchored window reset, another 200 USDT.

Thus nearly 400 USDT could be paid within one second. This did not overdraw net principal, but it contradicted a strict limit of 20% **in any consecutive 24 hours**. The initial finding test reproduced this behavior successfully. That initial overall run also had one separate TEST FIXTURE failure because the paused-splitter negative test lacked funds for its attempted top-up; the fixture was corrected to reach the intended rejection path rather than weaken its assertion.

### Remediation

`NexoraModel2Vault` now stores cumulative withdrawal checkpoints, coalescing withdrawals that have identical timestamps. An upper-bound binary search subtracts payments that expired at or before `now - 24 hours`; the live total is measured on **(now - 24 hours, now]**. Principal withdrawals and reward claims share the same total. The lookup is logarithmic in checkpoint history instead of scanning every previous payment.

- The demonstrated boundary maneuver is now rejected.
- Capacity returns separately as each payment becomes 24 hours old.
- Exactly-24h, same-timestamp aggregation, shared reward/principal caps, and randomized differential reference tests pass.
- The denominator remains the disclosed lifetime EXTERNAL gross-deposit basis, excluding Reinvest; actual payment remains bounded by matured net principal / funded reward balances. This denominator is an economic policy, not a guarantee of funds.
- The public `withdrawalWindows(address)` read signature is retained, but now returns a live rolling interval rather than the previous stored anchored-period snapshot. Integrations relying on its old interpretation must be updated.

## Callback hardening

`syncDirect` remains permissionless but now uses the reentrancy guard shared with deposit/Reinvest operations. This prevents an ERC20 callback from re-counting an already-mature child during a top-up's transient state, before its qualification timestamp is reset.

Actual hostile mock callbacks were exercised during company allocations. Tests confirm typed `ReentrancyGuardReentrantCall` rejection of attempts to reenter deposit, withdraw, reward claim, reinvest and referral sync. Ordinary sync after the new 24-hour qualification interval still succeeds. These mocks are not a claim that the intended real token is malicious; actual token deployment/governance must be verified independently.

## Completed 100-account lifecycle simulation

Each of 100 mock accounts:

1. Deposits 1,000 test units; history and gross reference record 1,000, backed net principal is 800.
2. Receives 10 test units of independently FUNDED allocated reward. The test mints and funds this reserve externally; it does not establish genuine market earnings or guaranteed daily yield.
3. Voluntarily reinvests 5: 4 become new locked net principal; 1 is allocated to the company splitter.
4. After simulated maturity, withdraws 200 on each of four eligible days, then the remaining 4 on the fifth; also claims the remaining funded reward of 5.

| Ledger outcome | Per user | All 100 users |
| --- | ---: | ---: |
| Historical gross external deposit | 1,000 | 100,000 |
| Separately funded reward | 10 | 1,000 |
| Net principal after reinvest | 804 | 80,400 |
| Reward left after reinvest | 5 | 500 |
| Total returned to user in this specific funded scenario | **809** | **80,900** |
| Owner/company allocations from entry plus reinvest | 201 | 20,100 |
| Final outstanding user principal and reward liabilities | 0 | 0 |

The company allocation total is owner **6,030** plus **1,407 to each of ten corporate recipients**. Total resources reconcile: 100,000 user input + 1,000 independently funded rewards = 80,900 user exits + 20,100 company allocations. There is no invented 1,000-USDT redeemable principal after a 20% upfront deduction.

All of this is an offline test harness, including simulated 90-day maturity. The 100-account lifecycle executes many calls within one test and consumes roughly 279 million aggregate test gas; **it is not a deployable single public-chain batch and does not establish public-chain transaction throughput or fees**.

## Additional behaviors verified

- All five VIP qualification levels, gross-capital thresholds and balanced-branch rules.
- Pre-funded three-level 15% / 7% / 3% referral accounting, including inactive ancestors without level compression.
- Three-level team-volume adjustments after partial exits; top-up/reinvest resets of direct qualification.
- Permanent referrers, self/future-parent rejection, 128-child boundary and explicit 129th-child rejection.
- Zero inputs, minimum/maximum gross deposits, exact cooldown boundaries, report replay prevention.
- Partial reward claims clipped to remaining daily capacity without losing residual credited rewards.
- Mixed base/referral reward reinvestment, pause/unpause behavior and mature exit availability during pause.
- Failed allocations do not consume report IDs or create unfunded balances; unsolicited donations do not automatically become reward reserves.
- Fee-on-transfer token rejection specifically on the real Model2 vault path; constructor asset/role/splitter validation.
- Test-token mint authorization and Testnet factory role handoff / chain rejection.
- Separate gross receipt, gross open reference, net capital and reward snapshot fields. A displayed withdrawal CAP is not evidence funds have matured.

## Still open: no mainnet go-live

1. **No verified public BNB Testnet deployment or real transaction hashes.** Simulated chain ID 97 is not a deployment. The three operational role addresses and a user-controlled testnet signing wallet/test BNB are required. The 11 supplied payout wallets are beneficiaries, not automatically the governance, funding or allocator roles.
2. **No independent audit and remediation sign-off.** Callback hardening and rolling-limit changes must themselves be reviewed. Tests do not establish compiler, dependency or economic safety.
3. **No verified beneficiary-control signatures or governance multisig signer/threshold evidence.** Correct checksum does not establish control.
4. **No production-site transaction integration/E2E sign-off.** The audited ABI and exact deployed addresses must be connected to the chosen primary site; upfront 20% allocation, 90-day lock, gross/net distinction and conditional reward policy must be visible before user consent.
5. **No independent realized-profit/source-of-funds evidence.** The 1%-2.5% daily figures remain conditional caps, not verified trading performance. New participant principal must not finance old participant rewards.
6. **Residual liveness/economic constraints:** principal tranches grow with each deposit/reinvest; extreme fragmented-history gas needs public-chain stress review. The permanent 128-direct cap can prevent additional referrals, including if unwanted referrals occupy slots. Lifetime deposit basis and reward maturity from first deposit must be expressly disclosed and evaluated.
7. **Legacy paths remain distinct.** The old `NexoraProfitVault` and old readiness documents are not the release artifact for Model2. The obsolete blocker script that inspects the old vault cannot certify the new one. The Model2 factory is Testnet-only; that guard does not prevent someone manually deploying a different/direct contract. No such deployment was performed here.

## Reproduction

In the repository's `smart-contracts` directory, use the pinned source/test snapshot and its declared Solidity/OpenZeppelin versions:

```bash
npm install --ignore-scripts --no-audit --no-fund
python3 scripts/check-beneficiary-config.py
forge test -vv --fuzz-runs 1024
forge coverage --report summary
npm audit --omit=dev --audit-level=high
```

The new dedicated workflow has read-only repository permissions and **no RPC signing, private-key access, deployment or fund-transfer step**. Its logs are archived as build artifacts. The later workflow-only commit `855170f67d7c27aa0dbc165570cc5a579f738c3c` additionally checks runtime/initcode size limits before executing tests; consult that run's result separately.

**Release decision: continue with reviewed TESTNET commissioning; do not accept real investor funds or declare mainnet ready.**
