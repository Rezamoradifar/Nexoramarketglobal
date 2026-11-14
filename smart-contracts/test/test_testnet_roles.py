import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("testnet_roles", ROOT / "scripts/check-testnet-roles.py")
roles = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(roles)


class TestTestnetRoleConfiguration(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT / "config/testnet-roles.candidate.json").read_text())

    def test_selected_owner_is_recorded_and_missing_roles_fail_closed(self):
        beneficiaries = json.loads((ROOT / "config/beneficiary-wallets.candidate.json").read_text())
        self.assertEqual(self.data["administrator"], beneficiaries["constructorWallets"][0])
        self.assertEqual(self.data["deployer"], self.data["administrator"])
        self.assertEqual(roles.validate(self.data), ["rewardFunder", "rewardAllocator"])
        result = subprocess.run([sys.executable, str(ROOT / "scripts/check-testnet-roles.py"), "--enforce"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("NEXORA_TESTNET_ROLES_INCOMPLETE", result.stdout)

    def test_wrong_chain_and_duplicate_operational_roles_are_rejected(self):
        self.data["chainId"] = 56
        with self.assertRaisesRegex(ValueError, "chain 97"):
            roles.validate(self.data)
        self.data["chainId"] = 97
        self.data["rewardFunder"] = self.data["administrator"]
        with self.assertRaisesRegex(ValueError, "must be distinct"):
            roles.validate(self.data)

    def test_deployer_may_be_one_of_the_operational_roles(self):
        self.data["rewardFunder"] = "0x1111111111111111111111111111111111111111"
        self.data["rewardAllocator"] = "0x2222222222222222222222222222222222222222"
        self.data["deployer"] = self.data["administrator"]
        with patch.object(roles, "checksum", side_effect=lambda address: address):
            self.assertEqual(roles.validate(self.data), [])


if __name__ == "__main__":
    unittest.main()
