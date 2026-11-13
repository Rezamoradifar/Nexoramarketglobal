#!/usr/bin/env python3
"""Exercise Model 2 against a private, disposable Anvil node.

This intentionally starts its own loopback-only node with chain ID 97 and
Anvil's disposable, unlocked development accounts. It never connects to a
public RPC, uses private keys, or deploys to BNB Testnet or Mainnet.
"""

from __future__ import annotations

import json
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UNIT = 10**18


class RpcError(RuntimeError):
    pass


def main() -> None:
    subprocess.run(["forge", "build", "--quiet"], cwd=ROOT, check=True)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    process = subprocess.Popen(
        ["anvil", "--host", "127.0.0.1", "--port", str(port),
         "--chain-id", "97", "--accounts", "20", "--silent"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    endpoint = f"http://127.0.0.1:{port}"

    def rpc(method: str, params: list) -> object:
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                           "params": params}).encode()
        request = urllib.request.Request(endpoint, body, {"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=5) as response:
            result = json.load(response)
        if "error" in result:
            raise RpcError(f"{method}: {result['error'].get('message', 'RPC error')}")
        return result["result"]

    def selector(signature: str) -> str:
        return subprocess.check_output(["cast", "sig", signature], text=True).strip()

    def word(value: str | int) -> str:
        number = int(value, 16) if isinstance(value, str) else value
        if not 0 <= number < 2**256:
            raise ValueError("Invalid ABI word")
        return f"{number:064x}"

    def data(signature: str, *args: str | int) -> str:
        return selector(signature) + "".join(word(arg) for arg in args)

    def call(address: str, signature: str, *args: str | int) -> int:
        result = rpc("eth_call", [{"to": address, "data": data(signature, *args)}, "latest"])
        return int(result, 16)

    def transact(sender: str, target: str | None, payload: str) -> dict:
        tx = {"from": sender, "data": payload, "gas": hex(20_000_000)}
        if target is not None:
            tx["to"] = target
        tx_hash = rpc("eth_sendTransaction", [tx])
        receipt = None
        for _ in range(100):
            receipt = rpc("eth_getTransactionReceipt", [tx_hash])
            if receipt:
                break
            time.sleep(0.05)
        if not receipt:
            raise TimeoutError(f"Local transaction was not mined: {tx_hash}")
        if int(receipt["status"], 16) != 1:
            trace = rpc("debug_traceTransaction", [tx_hash, {"disableStorage": True,
                                                             "disableMemory": True,
                                                             "disableStack": True}])
            steps = trace.get("structLogs", [])
            last_step = steps[-1] if steps else {}
            raise AssertionError(f"Local transaction failed: {tx_hash}; receipt={receipt}; "
                                 f"trace_failed={trace.get('failed')} last_opcode={last_step.get('op')}")
        return receipt

    def deploy(sender: str, contract: str, *args: str | int) -> str:
        bytecode = subprocess.check_output(
            ["forge", "inspect", contract, "bytecode"], cwd=ROOT, text=True
        ).strip()
        receipt = transact(sender, None, bytecode + "".join(word(arg) for arg in args))
        return receipt["contractAddress"]

    def expect(actual: int, expected: int, label: str) -> None:
        if actual != expected:
            raise AssertionError(f"{label}: expected {expected}, received {actual}")

    try:
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError("Local Anvil node exited before startup")
            try:
                if int(rpc("eth_chainId", []), 16) == 97:
                    break
            except (OSError, urllib.error.URLError):
                time.sleep(0.05)
        else:
            raise RuntimeError("Local Anvil node did not start")

        accounts = rpc("eth_accounts", [])
        deployer, admin, funder, allocator, member = accounts[:5]
        beneficiaries = accounts[5:16]
        token = deploy(deployer, "src/NexoraTestUSDT.sol:NexoraTestUSDT", admin)
        factory = deploy(deployer, "src/NexoraModel2TestnetFactory.sol:NexoraModel2TestnetFactory",
                         token, admin, funder, allocator, *beneficiaries)
        vault = "0x" + f"{call(factory, 'vault()'):040x}"
        splitter = "0x" + f"{call(factory, 'splitter()'):040x}"

        transact(admin, token, data("mintTestTokens(address,uint256)", member, 1_000 * UNIT))
        transact(member, token, data("approve(address,uint256)", vault, 1_000 * UNIT))
        transact(member, vault, data("deposit(uint256,address)", 1_000 * UNIT, 0))
        expect(call(token, "balanceOf(address)", vault), 800 * UNIT, "backed principal")
        expect(call(splitter, "claimable(address)", beneficiaries[0]), 60 * UNIT, "owner share")
        for beneficiary in beneficiaries[1:]:
            expect(call(splitter, "claimable(address)", beneficiary), 14 * UNIT, "company share")
        try:
            rpc("eth_call", [{"from": member, "to": vault,
                              "data": data("claimRewards()")}, "latest"])
            raise AssertionError("An early reward claim unexpectedly succeeded")
        except RpcError:
            pass

        rpc("evm_increaseTime", [24 * 60 * 60])
        rpc("evm_mine", [])
        transact(admin, token, data("mintTestTokens(address,uint256)", funder, 10 * UNIT))
        transact(funder, token, data("approve(address,uint256)", vault, 10 * UNIT))
        transact(funder, vault, data("fundRewards(uint256)", 10 * UNIT))
        transact(allocator, vault, data("allocateReward(address,uint256,bytes32)",
                                        member, 10 * UNIT, 1))
        transact(member, vault, data("reinvestRewards(uint256)", 4 * UNIT))
        expect(call(token, "balanceOf(address)", vault), 809 * UNIT + UNIT // 5,
               "vault balance after reinvest")
        expect(call(vault, "totalClaimableRewards()"), 6 * UNIT, "remaining rewards")
        expect(call(splitter, "claimable(address)", beneficiaries[0]),
               60 * UNIT + 24 * UNIT // 100, "owner share after reinvest")

        rpc("evm_increaseTime", [89 * 24 * 60 * 60])
        rpc("evm_mine", [])
        transact(member, vault, data("claimRewards()"))
        transact(member, vault, data("withdrawPrincipal(uint256)", 194 * UNIT))
        expect(call(token, "balanceOf(address)", member), 200 * UNIT, "member withdrawal")
        expect(call(vault, "remainingWithdrawalCap(address)", member), 0, "shared 24h cap")
        transact(beneficiaries[0], splitter, data("claim()"))
        expect(call(token, "balanceOf(address)", beneficiaries[0]),
               60 * UNIT + 24 * UNIT // 100, "owner claim")
        expect(call(vault, "isSolvent()"), 1, "vault solvency")
        expect(call(splitter, "isSolvent()"), 1, "splitter solvency")
        ui_member = accounts[16]
        transact(admin, token, data("mintTestTokens(address,uint256)", ui_member, 1_000 * UNIT))
        subprocess.run(["node", str(ROOT.parent / "tests/local-model2-wallet-e2e.mjs"),
                        endpoint, vault, token, ui_member], cwd=ROOT.parent, check=True)
        expect(call(vault, "isSolvent()"), 1, "solvency after wallet integration")
        print("LOCAL_MODEL2_E2E_OK: deposit, 11 shares, funding, reinvest, "
              "90-day claim, withdrawal, shared 24h cap and solvency")
        print("Local Anvil simulation only; no public-network transaction occurred.")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


if __name__ == "__main__":
    main()
