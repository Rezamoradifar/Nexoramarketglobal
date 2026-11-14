// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NexoraModel2Vault} from "../src/NexoraModel2Vault.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {FeeOnTransferMockNexora, SixDecimalTokenNexora} from "./NexoraAdversarialToken.t.sol";

interface VmModel2Callback {
    function warp(uint256) external;
    function prank(address) external;
    function chainId(uint256) external;
}

/** Local malicious mock only. No real token, address or chain is attacked. */
contract Model2CallbackMock is ERC20 {
    address public target;
    address public split;
    bytes public payload;
    uint256 public attempts;
    bool public succeeded;
    bytes4 public errorSelector;
    bool private inCallback;
    constructor() ERC20("TEST hostile callback", "TCALL") {}
    function mint(address recipient, uint256 amount) external { _mint(recipient, amount); }
    function arm(address vault, address splitter, bytes calldata data) external {
        target = vault; split = splitter; payload = data;
        attempts = 0; succeeded = false; errorSelector = bytes4(0);
    }
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool result = super.transferFrom(from, to, amount);
        if (!inCallback && from == target && to == split && payload.length != 0) {
            inCallback = true;
            ++attempts;
            (bool ok, bytes memory reason) = target.call(payload);
            succeeded = ok;
            if (reason.length >= 4) {
                bytes4 sel; assembly { sel := mload(add(reason, 32)) }
                errorSelector = sel;
            }
            inCallback = false;
        }
        return result;
    }
}

contract NexoraModel2CallbackSafetyTest {
    VmModel2Callback private constant vm = VmModel2Callback(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant U = 1e18;
    uint256 private constant T = 1_800_000_000;
    address private constant PARENT = address(0xAB01);
    address private constant CHILD = address(0xAB02);
    Model2CallbackMock private token;
    NexoraRevenueSplitter private splitter;
    NexoraModel2Vault private vault;
    address[11] private recipients;

    function setUp() public {
        vm.chainId(97);
        vm.warp(T);
        for (uint256 i; i < 11; ++i) recipients[i] = address(uint160(0xB100 + i));
        token = new Model2CallbackMock();
        splitter = new NexoraRevenueSplitter(address(token), address(this), address(this), recipients);
        vault = new NexoraModel2Vault(address(token), address(this), address(this), address(this), address(splitter));
        splitter.grantRole(splitter.FUNDER_ROLE(), address(vault));
        token.mint(PARENT, 1000 * U); token.mint(CHILD, 1000 * U);
        vm.prank(PARENT); token.approve(address(vault), type(uint256).max);
        vm.prank(CHILD); token.approve(address(vault), type(uint256).max);
        vm.prank(PARENT); vault.deposit(100 * U, address(0));
        vm.prank(CHILD); vault.deposit(100 * U, PARENT);
        vm.warp(T + 1 days); vault.syncDirect(CHILD);
    }
    function assertBlocked() private view {
        require(token.attempts() == 1, "callback was not actually exercised");
        require(!token.succeeded(), "callback unexpectedly succeeded");
        require(token.errorSelector() == bytes4(keccak256("ReentrancyGuardReentrantCall()")), "wrong protection caused rejection");
        require(vault.isSolvent() && splitter.isSolvent(), "token liabilities not backed");
    }
    function testCallbackCannotReactivateDirectDuringTopUp() public {
        token.arm(address(vault), address(splitter), abi.encodeCall(NexoraModel2Vault.syncDirect, (CHILD)));
        vm.prank(CHILD); vault.deposit(U, PARENT);
        assertBlocked();
        require(vault.getAccount(PARENT).activeDirects == 0, "parent retained premature qualification");
        require(!vault.getAccount(CHILD).countedInParent, "child prematurely counted");
        vm.warp(T + 2 days); vault.syncDirect(CHILD);
        require(vault.getAccount(PARENT).activeDirects == 1, "normal permissionless sync no longer works");
    }
    function testCallbackCannotReactivateDirectDuringReinvest() public {
        token.mint(address(this), U); token.approve(address(vault), U); vault.fundRewards(U);
        vault.allocateReward(CHILD, U / 2, bytes32(uint256(9)));
        token.arm(address(vault), address(splitter), abi.encodeCall(NexoraModel2Vault.syncDirect, (CHILD)));
        vm.prank(CHILD); vault.reinvestRewards(U / 2);
        assertBlocked();
        require(vault.getAccount(PARENT).activeDirects == 0, "reinvest callback bypassed maturity");
    }
    function testCallbacksCannotReenterDepositWithdrawalClaimOrReinvest() public {
        bytes[4] memory calls;
        calls[0] = abi.encodeCall(NexoraModel2Vault.deposit, (U, address(0)));
        calls[1] = abi.encodeCall(NexoraModel2Vault.withdrawPrincipal, (U));
        calls[2] = abi.encodeCall(NexoraModel2Vault.claimRewards, ());
        calls[3] = abi.encodeCall(NexoraModel2Vault.reinvestRewards, (U));
        for (uint256 i; i < 4; ++i) {
            token.arm(address(vault), address(splitter), calls[i]);
            vm.prank(CHILD); vault.deposit(U, PARENT);
            assertBlocked();
        }
    }
    function testFeeOnTransferRejectedByActualModel2VaultWithoutPartialCompanyCredit() public {
        FeeOnTransferMockNexora taxed = new FeeOnTransferMockNexora();
        NexoraRevenueSplitter s = new NexoraRevenueSplitter(address(taxed), address(this), address(this), recipients);
        NexoraModel2Vault v = new NexoraModel2Vault(address(taxed), address(this), address(this), address(this), address(s));
        s.grantRole(s.FUNDER_ROLE(), address(v));
        taxed.mint(CHILD, 1000 * U); vm.prank(CHILD); taxed.approve(address(v), type(uint256).max);
        vm.prank(CHILD); (bool ok, bytes memory reason) = address(v).call(abi.encodeCall(NexoraModel2Vault.deposit, (1000 * U, address(0))));
        require(!ok && reason.length >= 4, "taxed input accepted");
        bytes4 sel; assembly { sel := mload(add(reason, 32)) }
        require(sel == NexoraModel2Vault.FeeOnTransferNotSupported.selector, "wrong rejection");
        require(taxed.balanceOf(CHILD) == 1000 * U, "failed deposit lost funds");
        require(v.totalPrincipal() == 0 && s.totalClaimable() == 0, "failed deposit created liability");
    }
    function testModel2ConstructorRejectsBadAssetSplitterAndRole() public {
        bool created;
        try new NexoraModel2Vault(address(0), address(this), address(this), address(this), address(splitter)) { created = true; } catch {}
        require(!created, "zero asset accepted");
        try new NexoraModel2Vault(address(token), address(0), address(this), address(this), address(splitter)) { created = true; } catch {}
        require(!created, "zero admin accepted");
        try new NexoraModel2Vault(address(0x123), address(this), address(this), address(this), address(splitter)) { created = true; } catch {}
        require(!created, "EOA token accepted");
        SixDecimalTokenNexora six = new SixDecimalTokenNexora();
        try new NexoraModel2Vault(address(six), address(this), address(this), address(this), address(splitter)) { created = true; } catch {}
        require(!created, "wrong decimals accepted");
        try new NexoraModel2Vault(address(token), address(this), address(this), address(this), address(0)) { created = true; } catch {}
        require(!created, "zero splitter accepted");
        Model2CallbackMock other = new Model2CallbackMock();
        NexoraRevenueSplitter mismatch = new NexoraRevenueSplitter(address(other), address(this), address(this), recipients);
        try new NexoraModel2Vault(address(token), address(this), address(this), address(this), address(mismatch)) { created = true; } catch {}
        require(!created, "mismatching splitter asset accepted");
    }
}
