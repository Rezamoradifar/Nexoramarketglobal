# Nexora beneficiary address manifest — CANDIDATE ONLY

The account owner supplied **11 public EVM addresses**: wallet index **0** is the owner, followed by corporate payout wallets **1–10**. Their EIP-55 checksums, format, nonzero status and uniqueness were verified, and the manifest was integrated into Foundry unit tests.

**DO NOT USE FOR MAINNET UNTIL EACH RECIPIENT HAS PROVEN CONTROL OF THEIR ADDRESS.**

- File: [beneficiary-wallets.candidate.json](./beneficiary-wallets.candidate.json)
- Testnet chain ID: **97**, target BSC mainnet chain ID: **56** (the addresses use the same EVM address format).
- No private keys, seed phrases, or personal signing credentials are present.
- The contracts do not know whether these addresses belong to the intended individuals or companies; format checks **cannot** prove ownership.
- A recipient should independently sign a unique, time-limited message confirming their role, platform name, chain and this exact address. For smart contract wallets, use ERC-1271 verification. Record evidence privately where suitable; never collect seed phrases.
- These 11 wallets are **beneficiaries**, not privileged admin accounts. Governance admin multisig, rewards allocator and external revenue funder are separate roles and have not been supplied.
- Existing revenue-contract payout weights: **80%** independently-funded revenue to the separate rewards reserve, **6%** to the owner and **1.4% each** to ten corporate wallets. The splitter receives 20% and divides it **30/100 owner** and **7/100 each corporate wallet**.
- The user's later proposed Model 2 account display (historical gross deposit visible, net 80% backed principal) is **not integrated with real deposits/reinvestments**; do NOT present these wallet addresses as already receiving commissions on live deposits. The source must be legally reviewed and audited before activation.
- The actual vault has no owner/partner principal-withdrawal function. This should be independently verified with a full audit, privileged-role review and adverse-condition testing.

## Verification

From the `smart-contracts` working directory with Foundry installed:

```bash
python3 scripts/check-beneficiary-config.py
forge test -vv --match-contract NexoraConfiguredBeneficiariesTest
```

Both commands are **offline and safe to run** without sending transactions. The first validates EIP-55 checksum, uniqueness, constructor address order, fixed allocation weights and chain metadata. The second constructs the mocked vault/router/splitter and checks owner/ten-company claimables and absence of direct principal withdrawal privileges for those recipients.

## Do not infer

- Receipt of an address is **not** evidence its controller agreed to its role.
- A passing test is not a completed independent smart-contract audit.
- No real USDT was transferred, distributed or reserved by this branch.
- Do not use the candidate manifest for mainnet construction without recipient signatures, an independent review and production configuration sign-off.
