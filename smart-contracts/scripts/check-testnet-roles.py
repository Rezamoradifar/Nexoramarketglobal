#!/usr/bin/env python3
"""Validate public testnet role candidates; never sign or send transactions."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[1] / "config/testnet-roles.candidate.json"
ROLES = ("administrator", "rewardFunder", "rewardAllocator")


def checksum(address: str) -> str:
    result = subprocess.run(["cast", "to-check-sum-address", address],
                            capture_output=True, text=True, check=True, timeout=15)
    return result.stdout.strip()


def validate(data: dict) -> list[str]:
    if data.get("schemaVersion") != 1 or data.get("chainId") != 97:
        raise ValueError("This configuration must target BNB Testnet chain 97")
    missing = []
    seen_roles = set()
    for field in (*ROLES, "deployer"):
        address = data.get(field)
        if address is None:
            missing.append(field)
            continue
        if not isinstance(address, str) or not re.fullmatch(r"0x[0-9a-fA-F]{40}", address):
            raise ValueError(f"Invalid {field} address")
        if int(address[2:], 16) == 0 or address != checksum(address):
            raise ValueError(f"Zero or non-checksummed {field} address")
        normalized = address.lower()
        if field in ROLES:
            if normalized in seen_roles:
                raise ValueError("Administrator, funder and allocator must be distinct")
            seen_roles.add(normalized)
    return missing


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--enforce", action="store_true", help="Exit nonzero if any role is missing")
    args = parser.parse_args()
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8"))
        missing = validate(data)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"NEXORA_TESTNET_ROLES_INVALID: {exc}", file=sys.stderr)
        return 1
    print(f"Testnet admin candidate: {data.get('administrator') or 'not supplied'}")
    if missing:
        print("NEXORA_TESTNET_ROLES_INCOMPLETE: " + ", ".join(missing))
    else:
        print("NEXORA_TESTNET_ROLE_ADDRESSES_FORMAT_VALID")
    print("Wallet control, tBNB balances, multisig, and deployment are not verified.")
    return 2 if missing and args.enforce else 0


if __name__ == "__main__":
    sys.exit(main())
