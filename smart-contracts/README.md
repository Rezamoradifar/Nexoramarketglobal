# Nexora Model 2 — testnet prototype

**Status: unaudited, no verified deployment, and not approved for real funds.** This branch contains a separate executable `NexoraModel2Vault`, a testnet-only factory and a no-value test token. The older `NexoraProfitVault` is a different full-principal prototype and must not be used as the Model 2 deployment.

The Model 2 vault and the test token each reject construction outside chain ID 97. The factory independently enforces the same restriction. Chain ID alone is not proof that an RPC endpoint or deployment is trustworthy. No source file or automated test is a security audit, proof of realized profit, or authorization to use mainnet.

## Current prototype accounting

- A 1,000-token external deposit records 1,000 as historical gross deposited and open gross plan reference. The vault retains **800** as net principal and transfers **200** to the splitter. The owner may claim 60 and each of the ten company beneficiaries 14; these are allocations, not automatically completed wallet transfers.
- Reinvestment can only use credited, funded rewards. It applies the same 20% allocation and creates a new 90-day net-principal tranche.
- Principal tranches mature after 90 days from their own deposit or reinvestment. Reward claims mature 90 days after the first external deposit. Claims and principal withdrawals share a cap of 20% of lifetime gross external deposits per anchored 24-hour window; reinvestment does not increase this cap. No additional withdrawal fee is charged.
- Tier rates of 1%–2.5% are conditional caps, not guaranteed or automatic earnings. A distinct funder must supply reward tokens and an authorized allocator must submit an allocation. The contract does not prove those tokens came from trading profit. Referral credits are 15% / 7% / 3% of a funded base reward.
- The 11 beneficiary addresses in `config/beneficiary-wallets.candidate.json` have format and uniqueness checks. Control, legal roles and the separate administrative multisig are not established by those checks.

## Important differences from the currently published site

The live site is an older preview and its proposal must not be presented as an exact description of this branch. In particular, this prototype uses current **gross** open positions for three-level team volume; it does not calculate the lowest net balance over a prior 24-hour window. Its balance test requires the largest branch to be no more than 50% of total current volume; the older site describes a 50% contribution cap against a tier target. It also uses an individually anchored 24-hour reward limit, not the site's 00:00 UTC pro-rata settlement. `syncDirect` requires a transaction after maturity and no keeper is included. These economic and operational differences need owner confirmation and independent review before a production specification can be finalized; do not silently equate the two models.

## Local verification

Install Node.js, Foundry and the pinned OpenZeppelin dependency, then run:

```bash
cd smart-contracts
npm install --ignore-scripts --no-audit --no-fund
forge build --sizes
forge test -vv --fuzz-runs 1024
python3 scripts/test-local-model2.py
python3 scripts/check-mainnet-blockers.py --enforce
```

The last command deliberately exits nonzero while mainnet blockers remain. `test-local-model2.py` starts its own disposable loopback-only Anvil instance, performs local mock-token deposit, allocations, reinvestment, claim and withdrawal transactions, and exercises the frontend wallet encoder. Its time travel is a simulation, not a public BNB Testnet transaction or a 90-day live observation.

For a read-only check against an independently chosen BNB Testnet RPC, set `BSC_TESTNET_RPC_URL` and run `bash scripts/testnet-preflight.sh`. It checks the returned chain ID, the candidate registry and compilation; it neither signs nor broadcasts.

## Testnet deployment and frontend

Use a new, user-controlled funded **testnet** signer and separate public admin, funder and allocator addresses. Deploy `NexoraTestUSDT` first with the test-token owner, then `NexoraModel2TestnetFactory` with that token, the distinct role addresses and the ordered 11-wallet array. Verify the resulting vault, splitter, token, roles and source on the testnet explorer. Record deployment and canary transaction hashes. Never send keys or seed phrases in chat or commit them.

The unpublished React test panel requires both `VITE_NEXORA_MODEL2_TESTNET_VAULT` and `VITE_NEXORA_MODEL2_TESTNET_TOKEN` to be set to the verified testnet addresses. It rechecks chain 97, bytecode presence, the vault's token address, and the token's `NXTTEST` symbol and decimals before requesting user-confirmed test transactions. Address and symbol checks do **not** establish contract authenticity or replace source verification. An approval is for the entered amount, not an unlimited allowance.

## Remaining release gates

Public BNB Testnet deployment and explorer verification; signed canary tests; frontend-to-testnet integration on the actual site; final reconciliation of the plan and public disclosures; ownership/control confirmation for beneficiaries and a verified multisig; independently substantiated reward funding; independent security audit and remediation; legal review; and operational monitoring all remain open. Do not use the prototype to accept real investor funds.

Earlier policy and test documents in this directory describe historical snapshots or alternative models. They are retained for traceability, not as the current Model 2 specification.
