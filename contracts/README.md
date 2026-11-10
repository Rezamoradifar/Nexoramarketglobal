# NexoraFundedVault — BNB testnet ONLY

> **UNAUDITED PROTOTYPE — NEVER USE REAL ASSETS OR CUSTOMER FUNDS.**

## What is implemented

- USDT-style ERC20 deposits (6 or 18 decimals), minimum initial 10, maximum personal principal 50,000 tokens
- Individual principal withdrawals without admin approval, even if paused
- External operator-funded profit credits; token transfers are required for every credited unit
- Three-level referrals of **15% / 7% / 3% of explicitly funded user profit**, and no referral-on-referral
- Immutable sponsor links, exact funding checks, anti-reentrancy controls, pause of new deposits/settlements, two-step admin transfer
- Solvency check: token holdings >= principal + funded credits

## NOT implemented — must not be advertised as live

- No verified trading bot, P&L proofs, audit or on-chain determination of genuine investment earnings
- No guaranteed daily yield (1–2.5% daily percentages in the frontend are illustrative ceilings only)
- No on-chain, independently verified active-direct / team-volume tiers, 24-hour snapshots, branch cap, or Sybil-resistant accounts
- No yield accrual clock, automated distributions, deposit insurance, compounding, or mainnet rollout
- No UI wallet connection or regulatory approval

**Operator can fund user credits from its own wallet:** this proves payment was funded, NOT that profits were earned from actual trades. In production, independent reconciliation and real economic yield verification would be essential.

## Local tests

Prerequisites: Node 22+ and npm.

```bash
cd contracts
npm install
npm test
```

## BNB testnet deployment (chain ID 97)

Use a personal testnet wallet with **only test tBNB**; do not put private keys in GitHub, screenshots or this chat.

```bash
cd contracts
cp .env.example .env
# Set DEPLOYER_PRIVATE_KEY in local untracked .env ONLY.
# Optionally set TEST_TOKEN_ADDRESS for a mock token; without it a disposable MockUSDT is created.
npx hardhat run scripts/deploy-testnet.cjs --network bscTestnet
```

Testnet explorer: https://testnet.bscscan.com/

**Important**: Anyone can mint the bundled mock token. It has no value and must NEVER be mistaken for real USDT.

Deployment transactions require a wallet signature and cannot be executed by simply publishing code to GitHub. Real BNB mainnet deployment must follow an independent professional security audit, legal review, admin/treasury multisig design and full integrated tests.
