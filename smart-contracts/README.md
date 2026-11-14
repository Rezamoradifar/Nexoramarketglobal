# Nexora Model 2 — chain-56 candidate

**Status: locally tested candidate only. No deployed mainnet contract or independent audit is verified, and wallet transactions are not enabled.** The owner selected current gross open positions, a largest-branch limit of 50% of total team volume, and an individually anchored 24-hour allocation interval on 2026-11-14. The owner asked not to deploy on a public testnet. Local EVM simulations use mock tokens and do not broadcast.

The shared `NexoraModel2Core` contains the accounting. The existing `NexoraModel2Vault` remains chain-97 guarded; the new `NexoraModel2MainnetVault` and atomic `NexoraModel2MainnetFactory` require chain 56 and pin Binance-Peg USDT (`0x55d398326f99059fF775485246999027B3197955`). A chain ID, address and decimals check is not independent verification of a deployed contract or token.

## Terms of the candidate

- On a 1,000 USDT external entry, 1,000 is a gross historical/open-position reference, **800 is backed user principal**, and 200 is allocated to the splitter: 60 claimable by the owner and 14 by each of ten company wallets. Gross reference is not redeemable principal; splitter allocations are not automatically claimed.
- Reinvestment of already funded rewards repeats the 20% allocation. Each net-principal tranche is locked for 90 days from its own entry. Reward claims are locked 90 days from the first deposit. Principal and reward claims share a rolling 24-hour limit of 20% of lifetime external gross deposits; reinvestment does not increase it. No additional withdrawal fee is charged.
- The five daily caps (1%, 1.25%, 1.5%, 2%, 2.5%) are limits on authorized credits, not guaranteed earnings. A role must separately fund rewards and an allocator must submit each credit. The contract does not verify that funding is trading profit. Eligible uplines receive 15% / 7% / 3% of the funded base credit.
- Open gross reference counts across three levels. Higher tiers require the largest branch to be at most 50% of the overall team volume, plus the specified gross capital and direct thresholds. The first allocation is at least 24 hours after the latest deposit/reinvestment, and subsequent credits are at least 24 hours apart. There is no fixed 00:00 UTC settlement.
- `syncDirect` requires an on-chain call after a member qualifies. There is no verified keeper or automatic allocator. Branch balance uses an incrementally maintained max-heap rather than a fixed 128-direct limit; storage and gas behavior still need independent review.
- `config/beneficiary-wallets.candidate.json` has the supplied public recipients; format checks do not establish wallet control. Administrative/funder/allocator addresses are constructor inputs. Same-wallet roles are supported but are a single point of control, not independent governance. The earlier testnet-only role file is not proof of mainnet authorization or signer control.

## Verification

```bash
cd smart-contracts
npm install --ignore-scripts --no-audit --no-fund
forge build --sizes
forge test -vv
python3 scripts/check-beneficiary-config.py
python3 scripts/check-mainnet-blockers.py --enforce
```

Mainnet candidate tests set the chain ID to 56 in a local EVM and install mock token code at the canonical address; this does not exercise real USDT or the live chain. The last command deliberately reports remaining blockers and performs no RPC, signing or transaction. Passing local tests and static analysis is not a security audit. A controlled real-network canary, if performed after review, consumes real funds and is not yet done.

## Work still required

Independent smart-contract review and remediation, verified deployment artifacts and signers, evidence of beneficiaries' control, a credible externally funded reward source, an audited automation/monitoring path, original-site wallet integration, regulatory review and an operational incident plan are outstanding. The original Site is separate from the React test panel in this repository; neither is proof of a live financial product. No private keys or seed phrases belong in chat or source control.

Historical documents in this directory describe alternative proposals and do not override these selected terms.
