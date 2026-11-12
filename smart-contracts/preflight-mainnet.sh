#!/usr/bin/env bash
# Nexora BNB mainnet READ-ONLY preflight.
# NO chain writes, wallet signatures, or private keys.
set -Eeuo pipefail

EXPECTED_CHAIN_ID=56
EXPECTED_TOKEN='0x55d398326f99059fF775485246999027B3197955'
fatal() { echo "NEXORA_PREFLIGHT_BLOCKED: $*" >&2; exit 1; }
need() {
  local key="$1"
  [[ -n "$(printenv "$key" || true)" ]] || fatal "Missing $key (public address or RPC; NO private key required)"
}
for bin in cast awk tr; do command -v "$bin" >/dev/null || fatal "Missing CLI: $bin (install Foundry)"; done
need MAINNET_RPC_URL
need NEXORA_ADMIN_MULTISIG
need NEXORA_REVENUE_FUNDER
need NEXORA_REWARD_ALLOCATOR
need NEXORA_OWNER_WALLET
for n in $(seq -w 1 10); do need "NEXORA_PARTNER_$n"; done

echo 'NEXORA_MAINNET_PREFLIGHT_READ_ONLY'
echo 'Checking BNB Smart Chain mainnet chain ID...'
chain_id="$(cast chain-id --rpc-url "$MAINNET_RPC_URL" 2>/dev/null)" ||
  fatal 'RPC endpoint unavailable or invalid. RPC may be wrong; do not broadcast.'
[[ "$chain_id" == "$EXPECTED_CHAIN_ID" ]] ||
  fatal "RPC chain ID $chain_id is not BSC mainnet $EXPECTED_CHAIN_ID"

echo 'Checking 18-decimal Binance-Peg USDT token address...'
token_code="$(cast code "$EXPECTED_TOKEN" --rpc-url "$MAINNET_RPC_URL" 2>/dev/null)" ||
  fatal 'Unable to read token code'
[[ "$token_code" != '0x' && "$token_code" != '0x0' && -n "$token_code" ]] ||
  fatal 'Token contract has no code at expected address'
decimals="$(cast call "$EXPECTED_TOKEN" 'decimals()(uint8)' --rpc-url "$MAINNET_RPC_URL" 2>/dev/null)" ||
  fatal 'Token decimals() call failed'
[[ "$decimals" == '18' ]] ||
  fatal "Token decimals unexpected: $decimals, wanted 18"

echo 'Checking public wallet addresses, uniqueness and role separation...'
declare -A seen
validate_address() {
  local key="$1" value="$2" canonical normalized
  canonical="$(cast to-check-sum-address "$value" 2>/dev/null)" ||
    fatal "$key is not a valid EVM address"
  [[ "$canonical" != '0x0000000000000000000000000000000000000000' ]] ||
    fatal "$key is zero address"
  normalized="$(printf '%s' "$canonical" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "${seen[$normalized]:-}" ]]; then
    fatal "$key duplicates ${seen[$normalized]}"
  fi
  seen["$normalized"]="$key"
}
validate_address NEXORA_ADMIN_MULTISIG "$NEXORA_ADMIN_MULTISIG"
validate_address NEXORA_REVENUE_FUNDER "$NEXORA_REVENUE_FUNDER"
validate_address NEXORA_REWARD_ALLOCATOR "$NEXORA_REWARD_ALLOCATOR"
validate_address NEXORA_OWNER_WALLET "$NEXORA_OWNER_WALLET"
for n in $(seq -w 1 10); do
  var="NEXORA_PARTNER_$n"
  validate_address "$var" "$(printenv "$var")"
done
admin_code="$(cast code "$NEXORA_ADMIN_MULTISIG" --rpc-url "$MAINNET_RPC_URL" 2>/dev/null)" ||
  fatal 'Cannot query admin contract'
[[ "$admin_code" != '0x' && "$admin_code" != '0x0' && -n "$admin_code" ]] ||
  fatal 'Admin must be a DEPLOYED multisig/governance contract on BSC mainnet'
echo 'Admin address has code (this does not verify signers or threshold).'

echo
echo 'CONTRACT RULES:'
echo '  80% independently funded business revenue -> vault reward reserve'
echo '  6% -> owner; 1.4% each -> ten company wallets'
echo '  100% of each new deposit remains protected user principal'
echo '  Company payout for a deposit/reinvest requires NEW outside funds, not a deduction from principal'
echo '  100% of each user deposit remains in principal custody'
echo '  User deposits must NEVER be routed as business revenue'
echo
echo 'TECHNICAL PREFLIGHT ONLY: audit, multisig ownership, jurisdictional'
echo 'compliance, independently verified profits, and testnet launch NOT validated.'
echo 'NEXORA_MAINNET_TECHNICAL_PREFLIGHT_OK__NO_DEPLOYMENT'
