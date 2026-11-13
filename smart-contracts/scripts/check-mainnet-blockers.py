#!/usr/bin/env python3
"""Fail-closed, non-transactional mainnet readiness record for Nexora.

CI invokes this script in REPORT mode (exit code 0) so test results remain
separate from financial launch authorization. --enforce exits nonzero whenever
independent attestations and production features are missing.

This script does NOT verify legal compliance, security audits, or token origin
and cannot substitute for independent reviewers.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
VAULT = ROOT / "src" / "NexoraProfitVault.sol"
PREVIEW = ROOT / "src" / "NexoraEntryAllocationPreview.sol"
MODEL2 = ROOT / "src" / "NexoraModel2Vault.sol"
CONFIG = ROOT / "config" / "beneficiary-wallets.candidate.json"


def collect_release_blockers() -> list[str]:
    blockers = []
    vault_source = VAULT.read_text(encoding="utf-8")
    preview_source = PREVIEW.read_text(encoding="utf-8")
    if MODEL2.is_file() and "function deposit(" in MODEL2.read_text(encoding="utf-8"):
        blockers.append(
            "MODEL_2_TESTNET_PROTOTYPE_ONLY: the separate gross/net vault has "
            "no verified deployment, independent audit, or production approval"
        )
    elif "a.principal = afterDeposit;" in vault_source:
        blockers.append(
            "MODEL_2_NOT_IN_VAULT: the legacy vault credits gross principal; "
            "the separate executable model is missing"
        )
    if "function preview(" in preview_source and "function deposit(" not in preview_source:
        blockers.append("MODEL_2_PRODUCTION_INTEGRATION_UNVERIFIED: the preview and "
                        "testnet prototype are not a deployed financial product")
    if not CONFIG.is_file():
        blockers.append("BENEFICIARIES_MISSING: cannot find candidate registry")
    else:
        blockers.append(
            "BENEFICIARIES_NOT_OWNERSHIP_VERIFIED: address checksums are not "
            "proof of wallet/company control; require role-specific signatures"
        )

    # External evidence must be independently submitted and checked by the
    # responsible reviewers, not inferred from passing tests or self-asserted
    # environment variables. Current source supplies none of those signoffs.
    blockers.extend([
        "NO_INDEPENDENT_SECURITY_AUDIT: Solidity contracts are unaudited",
        "NO_BSC_TESTNET_CANARY: no verified chain-97 deploy and transaction results",
        "NO_VERIFIED_ADMIN_MULTISIG: no real signer/threshold verification",
        "NO_REVENUE_ORIGIN_ATTESTATION: source of investor rewards not demonstrated",
        "NO_COMPLIANCE_SIGNOFF: very high yield tiers and fees require legal review",
        "NO_PRODUCTION_UI_WALLET_AUDIT: live site/back-end/contract integration unverified",
        "NO_LIVE_MARKET_FEED_INTEGRATION_AUDIT: no independently verified global-market adapter",
        "NO_DEPLOYMENT_BYTECODE_SIGNOFF: no pinned audited artifact and explorer verification",
    ])
    return blockers


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--enforce", action="store_true",
        help="Fail the process unless all independently checked mainnet gates pass",
    )
    args = parser.parse_args()
    blockers = collect_release_blockers()
    print(f"NEXORA_MAINNET_GATE_BLOCKED: {len(blockers)} independent blockers")
    for i, blocker in enumerate(blockers, 1):
        print(f"  {i:02d}. {blocker}")
    print("UNIT_TEST_SUCCESS_IS_NOT_MAINNET_APPROVAL")
    print("No RPC operations, signatures, private keys, USDT transfers or deployments.")
    if args.enforce:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
