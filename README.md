# Nexora Markets — Midnight Obsidian 3D (React)

Faithful working React/Vite implementation of the approved, cinematic **black / violet / cyan English-language design**. The original generated concept art contained illustrative numbers, an "Active" smart contract status and statistics which were not independently verified. This implementation deliberately avoids those claims.

## Run

```bash
npm install
npm run dev
# http://localhost:3080
```

Production build: `npm run build`. Production static assets are emitted into `dist/`.

## Preview boundaries

- Frontend only. Smart-contract deployments, wallets, deposits, withdrawals, login and payouts are **disabled**.
- Five conditional *hypothetical* daily payout caps: 1%, 1.25%, 1.5%, 2%, 2.5%; not guaranteed and not sourced from verified net profits.
- Referral illustrations: 15%, 7%, 3% of *settled* profit, not deposits.
- Public CoinGecko market quotes are fetched in the browser; when the API is unavailable there are no fabricated fallback prices.
- Account button opens an honest pre-launch message. The rank calculator is a front-end simulator only.
- Never present arbitrary sample TVL, user counts or payouts as real data.

## Deployment

Existing VPS deployment scripts in the GitHub repository build the `main` branch into `/opt/nexora-markets/releases` and serve via Nginx. Changes committed to GitHub are not automatically deployed to the VPS; an authorized deployment is a separate step. Keep SSL and unrelated vhosts unchanged.