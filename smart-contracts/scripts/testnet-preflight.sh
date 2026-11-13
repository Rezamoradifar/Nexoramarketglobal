#!/usr/bin/env bash
# Nexora Model2: READ-ONLY BSC TESTNET preflight.
# No deployment, signing, tokens, approvals, minting or transfers.
set -Eeuo pipefail

fail(){ echo "NEXORA_TESTNET_PREFLIGHT_BLOCKED: $*" >&2; exit 1; }
command -v cast >/dev/null || fail 'Foundry cast is required.'
command -v forge >/dev/null || fail 'Foundry forge is required.'
command -v python3 >/dev/null || fail 'Python3 is required.'
[[ -n "${BSC_TESTNET_RPC_URL:-}" ]] || fail 'Supply a trusted BSC TESTNET RPC endpoint.'
id="$(cast chain-id --rpc-url "$BSC_TESTNET_RPC_URL" 2>/dev/null)" ||
  fail 'RPC endpoint unavailable.'
[[ "$id" == "97" ]] ||
  fail "Incorrect RPC chain ID $id. MUST BE 97. Never use BSC mainnet 56."

echo 'BNB Testnet RPC verified: chain ID 97'
echo 'Validating 11 public beneficiary addresses and fixed allocations...'
python3 scripts/check-beneficiary-config.py || fail 'Recipient registry invalid'
echo 'Checking compiled contract runtime sizes (EIP-170 enabled)...'
forge build --sizes >/dev/null || fail 'Contract build or size verification failed'

echo 'NEXORA_TESTNET_READ_ONLY_PREFLIGHT_OK__NO_BROADCAST'
echo 'Still required: funded tBNB signer and testnet admin/funder/allocator'
echo 'public addresses; signed recipient role confirmation; real testnet canary'
echo 'transactions; independently checked source, audit and compliance.'
