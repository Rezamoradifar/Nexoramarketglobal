#!/usr/bin/env bash
# Read-only verification AFTER a formally approved, audited mainnet deployment.
# Does not deploy, upgrade, allocate, claim, approve or transfer any tokens.
set -Eeuo pipefail

fatal(){ echo "NEXORA_POSTDEPLOY_BLOCKED: $*" >&2; exit 1; }
required(){
  [[ -n "$(printenv "$1" || true)" ]] ||
    fatal "Missing $1 (read-only RPC or public address only)"
}
for command_name in cast tr; do command -v "$command_name" >/dev/null || fatal "Missing $command_name"; done
required MAINNET_RPC_URL
required NEXORA_FACTORY_ADDRESS
required NEXORA_ADMIN_MULTISIG
required NEXORA_OWNER_WALLET
for n in $(seq -w 1 10); do required "NEXORA_PARTNER_$n"; done

chain="$(cast chain-id --rpc-url "$MAINNET_RPC_URL" 2>/dev/null)" ||
  fatal "RPC unavailable"
[[ "$chain" == "56" ]] || fatal "Chain ID $chain is not BSC mainnet 56"

call(){
  local addr="$1" fn="$2"
  shift 2
  cast call "$addr" "$fn" "$@" --rpc-url "$MAINNET_RPC_URL" 2>/dev/null ||
    fatal "Read failed: $fn at $addr"
}
same(){
  local got want
  got="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  want="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  [[ "$got" == "$want" ]] || fatal "$3 mismatch: expected $2, got $1"
}
expect(){
  [[ "$1" == "$2" ]] || fatal "$3 mismatch: expected $2, got $1"
}

FACTORY="$NEXORA_FACTORY_ADDRESS"
VAULT="$(call "$FACTORY" 'vault()(address)')"
SPLITTER="$(call "$FACTORY" 'splitter()(address)')"
ROUTER="$(call "$FACTORY" 'router()(address)')"

expected_token='0x55d398326f99059fF775485246999027B3197955'
same "$(call "$VAULT" 'asset()(address)')" "$expected_token" "Vault token"
same "$(call "$SPLITTER" 'asset()(address)')" "$expected_token" "Splitter token"
same "$(call "$ROUTER" 'asset()(address)')" "$expected_token" "Router token"
same "$(call "$ROUTER" 'vault()(address)')" "$VAULT" 'Router vault'
same "$(call "$ROUTER" 'splitter()(address)')" "$SPLITTER" 'Router splitter'
same "$(call "$FACTORY" 'governanceAdmin()(address)')" "$NEXORA_ADMIN_MULTISIG" 'Admin'
expect "$(call "$ROUTER" 'VAULT_BPS()(uint256)')" '8000' 'Vault percentage'
expect "$(call "$ROUTER" 'WALLETS_BPS()(uint256)')" '2000' 'Wallet pool percentage'
expect "$(call "$SPLITTER" 'sharesBps(uint256)(uint16)' 0)" '5000' 'Owner split percentage'
same "$(call "$SPLITTER" 'payoutWallets(uint256)(address)' 0)" "$NEXORA_OWNER_WALLET" 'Owner wallet'
for n in $(seq -w 1 10); do
  index=$((10#$n))
  partvar="NEXORA_PARTNER_$n"
  same "$(call "$SPLITTER" 'payoutWallets(uint256)(address)' "$index")" "${!partvar}" "Partner $n"
  expect "$(call "$SPLITTER" 'sharesBps(uint256)(uint16)' "$index")" '500' "Partner $n split percentage"
done

for c in "$VAULT" "$SPLITTER"; do
  role="$(call "$c" 'DEFAULT_ADMIN_ROLE()(bytes32)')"
  expect "$(call "$c" 'hasRole(bytes32,address)(bool)' "$role" "$NEXORA_ADMIN_MULTISIG")" 'true' 'Admin governance'
  expect "$(call "$c" 'hasRole(bytes32,address)(bool)' "$role" "$FACTORY")" 'false' 'Factory has no admin'
  funder_role="$(call "$c" 'FUNDER_ROLE()(bytes32)')"
  expect "$(call "$c" 'hasRole(bytes32,address)(bool)' "$funder_role" "$ROUTER")" 'true' 'Router funder'
  expect "$(call "$c" 'hasRole(bytes32,address)(bool)' "$funder_role" "$FACTORY")" 'false' 'Factory funder revoked'
done

expect "$(call "$VAULT" 'isSolvent()(bool)')" 'true' 'Vault solvency'
expect "$(call "$SPLITTER" 'isSolvent()(bool)')" 'true' 'Splitter solvency'

echo "NEXORA_POSTDEPLOY_READONLY_OK"
echo "Factory: $FACTORY"
echo "Vault: $VAULT"
echo "Splitter: $SPLITTER"
echo "Router: $ROUTER"
echo "80% vault / 10% owner / 1% each partner verified ON CHAIN."
echo "This does NOT verify audits, legal clearance, all historical admin grants,"
echo "business profits, site security, token peg, or user-KYC policies."
