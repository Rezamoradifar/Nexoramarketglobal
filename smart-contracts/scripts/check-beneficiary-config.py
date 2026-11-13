#!/usr/bin/env python3
"""Offline public-address syntax, EIP-55, uniqueness and ratios validation.

This script reads only a local file and runs Foundry cast locally.
It does not call an RPC, access wallets, or transmit transactions.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

FILENAME = Path(__file__).resolve().parents[1] / "config" / "beneficiary-wallets.candidate.json"


def fail(message: str) -> None:
    print(f"NEXORA_BENEFICIARIES_BLOCKED: {message}", file=sys.stderr)
    raise SystemExit(1)


def checksum(address: str) -> str:
    try:
        result = subprocess.run(
            ["cast", "to-check-sum-address", address],
            capture_output=True, text=True, timeout=15, check=True,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        fail(f"Cannot verify EIP-55 checksum: {exc}")
    return result.stdout.strip()


def validate() -> None:
    data = json.loads(FILENAME.read_text(encoding="utf-8"))
    if data.get("testnetChainId") != 97 or data.get("targetMainnetChainId") != 56:
        fail("Wrong target chain IDs")
    ratios = data["revenueSplitBps"]
    if ratios != {
        "vaultRewardReserve": 8000, "owner": 600,
        "eachCompany": 140, "companyCount": 10,
    }:
        fail("Wrong 80% / 6% / 1.4% x 10 ratios")
    if ratios["vaultRewardReserve"] + ratios["owner"] + 10 * ratios["eachCompany"] != 10000:
        fail("Shares do not total 10,000 bps")
    if data["splitterPoolWeights"] != {"owner": 30, "eachCompany": 7, "total": 100}:
        fail("Wrong 30 + 10 x 7 splitter weights")

    recipients = data.get("recipients")
    constructor = data.get("constructorWallets")
    if not isinstance(recipients, list) or len(recipients) != 11:
        fail("Must supply 11 recipient records")
    if not isinstance(constructor, list) or len(constructor) != 11:
        fail("Must supply 11 constructor addresses")
    seen = set()
    for i, record in enumerate(recipients):
        role = "OWNER" if i == 0 else f"COMPANY_{i:02d}"
        if record.get("index") != i or record.get("role") != role:
            fail(f"Invalid index or role at {i}")
        if record.get("grossRevenueBps") != (600 if i == 0 else 140):
            fail(f"Incorrect overall share for {role}")
        if record.get("ofTwentyPercentPoolWeight") != (30 if i == 0 else 7):
            fail(f"Incorrect splitter weight for {role}")
        address = record.get("address")
        if not isinstance(address, str) or not re.fullmatch(r"0x[0-9a-fA-F]{40}", address):
            fail(f"Invalid EVM address for {role}")
        if int(address[2:], 16) == 0:
            fail(f"Zero address for {role}")
        if address != checksum(address):
            fail(f"Invalid EIP-55 casing for {role}")
        if constructor[i] != address:
            fail(f"Constructor wallet order mismatch for {role}")
        normalized = address.lower()
        if normalized in seen:
            fail(f"Duplicate wallet for {role}")
        seen.add(normalized)

    print("NEXORA_BENEFICIARIES_CANDIDATE_VALID")
    print("11 unique public addresses, valid EIP-55 checksums and fixed payout shares.")
    print("No on-chain ownership signatures, funds, or deployment verified.")


if __name__ == "__main__":
    validate()
