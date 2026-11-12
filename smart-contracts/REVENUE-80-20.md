# Nexora fixed revenue routing: 80% vault / 10% owner / 10% ten partners

**Prototype only. Not audited, not deployed.**

## Revenue flow (NOT customer principal)

A deposit from a user goes directly to NexoraProfitVault.deposit. 100% of the principal remains user-owned and withdrawable. No fee is taken from user deposits.

A separate authorized revenue funder calls NexoraRevenueRouter.fundAndRoute with an amount and a unique accounting evidence ID. The router performs the following **atomically** in one transaction:

| Destination | Share of funded business revenue | Example from 1,000 USDT |
| --- | ---: | ---: |
| NexoraProfitVault unallocated reward reserve | **80%** | 800 USDT |
| NexoraRevenueSplitter — owner address (wallet 0) | **10%** | 100 USDT |
| NexoraRevenueSplitter — partners (wallets 1–10) | **10% total** | 100 USDT (10 USDT each) |
| **Total** | **100%** | **1,000 USDT** |

The eleven beneficiaries divide **only the 20% pool**; they receive none of customer principal. Their **percentages are fixed in Solidity**: owner (index 0) receives **50% of the 20% pool**, equivalent to **10% of the total routed revenue**; every partner (indices 1–10) receives **5% of the 20% pool**, equivalent to **1% of total routed revenue** each. Only the 11 *public payout addresses* remain to be supplied before deployment. For amounts smaller than whole cents, integer-token-unit rounding can allocate tiny dust to the owner; the sum remains exact.

The 80% remains in the vault as a separate **unallocated reward reserve**, not as investor principal. Later credits to users and referrers are subject to authorization, tier caps, and available reward funding. No daily payment is automatic or guaranteed.

The router requires a unique evidence ID to prevent replay. An ID **does not prove economic net profit**; real financial statements and independent verification remain necessary.

## Deployment prerequisites

1. Independently verify the 18-decimal token addresses on the chosen chain. Begin on BNB testnet using a mock token.
2. Deploy the principal-safe vault and the eleven-wallet splitter with 11 distinct, nonzero public addresses. The splitter **does not accept arbitrary percentages**; its code fixes owner at 5,000 BPS of wallet pool and each partner at 500 BPS.
3. Deploy the revenue router using exactly the same token, with the vault and splitter addresses.
4. Grant each destination's FUNDER_ROLE to the router contract. Revoke previous direct funding permissions from temporary test funder wallets to enforce the split in ordinary operation. The DEFAULT_ADMIN_ROLE can still change role assignments and must be governed independently.
5. An authorized revenue wallet approves only the router, then calls fundAndRoute. If any destination fails, the complete transfer reverts.
6. Both vault reserve and wallet claims remain fully funded. Beneficiaries can claim their own balances. Customer deposits do not use this router.

## Safety caveats

- No trading, interest generation, or independent proof of profit is implemented.
- The revenue wallet must never fund this router with entrusted customer principal or with amounts backing previously credited user rewards.
- The platform's business model, 1%–2.5% daily caps, and the 15%/7%/3% referral payouts require independent economic, legal and security review.
- No upgrade, admin sweep, forced customer withdrawal, or migration from existing contracts is included.
- For real-money operations, establish custody policy, audited source-of-funds reporting, multisig access controls, external audit and signed beneficiary agreements.
- This is an **unmerged draft PR** and has no deployed chain address.

**Before mainnet:** the 80/10/1×10 shares are fixed. Supply the owner's public payout address and each of the ten partners' public payout addresses for final deployment parameters. Never share seed phrases or private keys.
