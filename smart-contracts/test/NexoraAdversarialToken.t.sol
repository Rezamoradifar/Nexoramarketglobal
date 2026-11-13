// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NexoraProfitVault} from "../src/NexoraProfitVault.sol";
import {NexoraRevenueRouter} from "../src/NexoraRevenueRouter.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";

interface VmAdversarialToken {
    function prank(address) external;
}

/** Test-only hostile ERC20: deducts 1% from each non-mint transfer. */
contract FeeOnTransferMockNexora is ERC20 {
    constructor() ERC20("Fee token", "FEE") {}
    function mint(address target, uint256 amount) external {
        _mint(target, amount);
    }
    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = amount / 100;
            super._update(from, to, amount - fee);
            if (fee != 0) super._update(from, address(0xDEAD), fee);
        } else {
            super._update(from, to, amount);
        }
    }
}

/** Test-only 6-decimal ERC20 that must be rejected at deployment. */
contract SixDecimalTokenNexora is ERC20 {
    constructor() ERC20("Six decimal stablecoin", "SIX") {}
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract NexoraAdversarialTokenTest {
    VmAdversarialToken private constant vm =
        VmAdversarialToken(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant U = 1e18;
    address private constant ALICE = address(0xA11CE);

    function testFeeOnTransferCannotCreateUnfundedUserPrincipal() public {
        FeeOnTransferMockNexora token = new FeeOnTransferMockNexora();
        NexoraProfitVault vault = new NexoraProfitVault(
            address(token), address(this), address(this), address(this)
        );
        token.mint(ALICE, 1_000 * U);
        vm.prank(ALICE);
        token.approve(address(vault), type(uint256).max);

        vm.prank(ALICE);
        (bool ok,) = address(vault).call(
            abi.encodeCall(NexoraProfitVault.deposit, (100 * U, address(0)))
        );
        require(!ok, "Fee-on-transfer token led to unbacked principal");
        require(vault.totalPrincipal() == 0, "Principal increased despite revert");
        require(token.balanceOf(address(vault)) == 0, "Transfer did not revert atomically");
        require(token.balanceOf(ALICE) == 1_000 * U, "User lost tokens after revert");
        require(vault.isSolvent(), "Vault insolvency after revert");
    }

    function testFeeOnTransferCannotProduceUnbackedRevenuePool() public {
        FeeOnTransferMockNexora token = new FeeOnTransferMockNexora();
        NexoraProfitVault vault = new NexoraProfitVault(
            address(token), address(this), address(this), address(this)
        );
        address[11] memory beneficiaries;
        for (uint256 i; i < 11; ++i) beneficiaries[i] = address(uint160(0x900 + i));
        NexoraRevenueSplitter splitter = new NexoraRevenueSplitter(
            address(token), address(this), address(this), beneficiaries
        );
        NexoraRevenueRouter router = new NexoraRevenueRouter(
            address(token), address(vault), address(splitter), address(this), address(this)
        );
        vault.grantRole(vault.FUNDER_ROLE(), address(router));
        splitter.grantRole(splitter.FUNDER_ROLE(), address(router));
        token.mint(address(this), 1_000 * U);
        token.approve(address(router), 1_000 * U);

        bytes32 evidenceId = bytes32(uint256(12345));
        (bool ok,) = address(router).call(
            abi.encodeCall(NexoraRevenueRouter.fundAndRoute, (1_000 * U, evidenceId))
        );
        require(!ok, "Fee-on-transfer revenue was accepted");
        require(!router.usedEvidenceIds(evidenceId), "Failed report marked used");
        require(vault.unallocatedRewards() == 0, "Reward reserve was inflated");
        require(splitter.totalClaimable() == 0, "Company balances were inflated");
        require(token.balanceOf(address(router)) == 0, "Router kept funds on revert");
        require(token.balanceOf(address(vault)) == 0, "Vault received tokens despite revert");
        require(token.balanceOf(address(splitter)) == 0, "Splitter received tokens despite revert");
    }

    function testWrongTokenDecimalsRejectVaultAndSplitterAtDeployment() public {
        SixDecimalTokenNexora token = new SixDecimalTokenNexora();
        bool vaultCreated;
        try new NexoraProfitVault(
            address(token), address(this), address(this), address(this)
        ) returns (NexoraProfitVault) {
            vaultCreated = true;
        } catch {}
        require(!vaultCreated, "6-decimal vault creation accepted");

        address[11] memory beneficiaries;
        for (uint256 i; i < 11; ++i) beneficiaries[i] = address(uint160(0xC00 + i));
        bool splitterCreated;
        try new NexoraRevenueSplitter(
            address(token), address(this), address(this), beneficiaries
        ) returns (NexoraRevenueSplitter) {
            splitterCreated = true;
        } catch {}
        require(!splitterCreated, "6-decimal splitter creation accepted");
    }
}
