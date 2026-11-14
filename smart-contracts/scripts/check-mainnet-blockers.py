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
CONFIG = ROOT / "config" / "beneficiary-wallets.candidate.json"


def collect_release_blockers() -> list[str]:
    blockers = []
    if not (ROOT / "src" / "NexoraModel2MainnetVault.sol").is_file():
        blockers.append("MODEL_2_MAINNET_CANDIDATE_MISSING: no chain-56 candidate exists")
    else:
        blockers.append("MODEL_2_MAINNET_CANDIDATE_UNVERIFIED: local candidate has no independent audit, verified deployment or bytecode approval")
    blockers.append("MODEL_2_SITE_INTEGRATION_UNVERIFIED: the original site has no verified mainnet wallet/contract integration")
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
        "NO_REVIEWED_MAINNET_CANARY: no controlled mainnet transactions have been performed after audit and deployment",
        "NO_VERIFIED_SYNC_AND_ALLOCATION_KEEPER: direct synchronization and funded daily allocation are not automated",
        "NO_VERIFIED_ADMIN_SIGNER_CONTROL: governance and operational wallet control are not verified",
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
