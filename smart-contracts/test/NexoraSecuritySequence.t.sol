// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraProfitVault} from "../src/NexoraProfitVault.sol";
import {NexoraRevenueRouter} from "../src/NexoraRevenueRouter.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {MockUSDT} from "./MockUSDT.sol";

interface VmSecurity {
    function prank(address) external;
    function warp(uint256) external;
}

/**
 * MAINNET PREPARATION ONLY. These integration tests use a local mock ERC20,
 * not a real BSC Testnet deployment or independent security audit.
 *
 * A passing test must NOT be presented as permission to receive USDT.
 */
contract NexoraSecuritySequenceTest {
    VmSecurity private constant vm =
        VmSecurity(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant U = 1e18;
    address private constant ALICE = address(0xA11CE);
    address private constant OWNER = address(0x700);
    address private constant COMPANY = address(0x701);

    MockUSDT private token;
    NexoraProfitVault private vault;
    NexoraRevenueRouter private router;
    NexoraRevenueSplitter private splitter;
    address[11] private wallets;

    function setUp() public {
        vm.warp(100 days);
        token = new MockUSDT();
        vault = new NexoraProfitVault(address(token), address(this), address(this), address(this));
        wallets[0] = OWNER;
        for (uint256 i = 1; i < 11; ++i) wallets[i] = address(uint160(0x700 + i));
        splitter = new NexoraRevenueSplitter(
            address(token), address(this), address(this), wallets
        );
        router = new NexoraRevenueRouter(
            address(token), address(vault), address(splitter), address(this), address(this)
        );
        vault.grantRole(vault.FUNDER_ROLE(), address(router));
        splitter.grantRole(splitter.FUNDER_ROLE(), address(router));
        vault.revokeRole(vault.FUNDER_ROLE(), address(this));
        splitter.revokeRole(splitter.FUNDER_ROLE(), address(this));

        token.mint(ALICE, 100_000 * U);
        vm.prank(ALICE);
        token.approve(address(vault), type(uint256).max);
        token.mint(address(this), 1_000_000 * U);
        token.approve(address(router), type(uint256).max);
    }

    function _deposit(uint256 amount) private {
        vm.prank(ALICE);
        vault.deposit(amount, address(0));
    }

    function _eq(uint256 a, uint256 b) private pure {
        require(a == b, "Unexpected amount");
    }

    function _assertLedgerSolvent() private view {
        _eq(
            token.balanceOf(address(vault)),
            vault.totalPrincipal() + vault.unallocatedRewards()
                + vault.totalClaimableRewards()
        );
        require(vault.isSolvent(), "Vault is insolvent");
        require(splitter.isSolvent(), "Splitter is insolvent");
        _eq(token.balanceOf(address(splitter)), splitter.totalClaimable());
        _eq(token.balanceOf(address(router)), 0);
    }

    function testCurrentVaultDoesNOTImplementDeposit20PercentModel2() public {
        // A deliberate RED FLAG: the owner has approved a DIFFERENT economic
        // model where gross 1000 is recorded, 800 net is backed, and a gross
        // reference may be used for a conditional tier. That is NOT live code.
        _deposit(1_000 * U);
        _eq(vault.getAccount(ALICE).principal, 1_000 * U);
        _eq(vault.totalPrincipal(), 1_000 * U);
        _eq(splitter.totalFunded(), 0);
        _eq(splitter.claimable(OWNER), 0);
        _eq(splitter.claimable(COMPANY), 0);
        _assertLedgerSolvent();
    }

    function testOneDepositRewardReinvestAndClaimsPreserveAllLiabilities() public {
        _deposit(1_000 * U);
        router.fundAndRoute(1_000 * U, bytes32(uint256(1)));

        _eq(splitter.claimable(OWNER), 60 * U);
        _eq(splitter.claimable(COMPANY), 14 * U);
        _assertLedgerSolvent();

        vm.warp(block.timestamp + 1 days);
        vault.allocateReward(ALICE, 10 * U, bytes32(uint256(2)));
        vm.prank(ALICE);
        vault.reinvestRewards(4 * U);
        _eq(vault.getAccount(ALICE).principal, 1_004 * U);
        _eq(vault.getAccount(ALICE).baseRewards, 6 * U);
        _eq(vault.totalClaimableRewards(), 6 * U);
        _eq(vault.unallocatedRewards(), 790 * U);
        _assertLedgerSolvent();

        // Only the fully mature first tranche can be withdrawn.
        vm.warp(block.timestamp + 90 days);
        uint256 beforeAlice = token.balanceOf(ALICE);
        vm.prank(ALICE);
        vault.withdrawPrincipal(200 * U);
        _eq(token.balanceOf(ALICE), beforeAlice + 200 * U);
        _eq(vault.remainingWithdrawalCap(ALICE), 0);
        _assertLedgerSolvent();

        // A reward claim must share the SAME 24-hour withdrawal allowance.
        vm.prank(ALICE);
        (bool ok,) = address(vault).call(abi.encodeCall(NexoraProfitVault.claimRewards, ()));
        require(!ok, "Claim bypassed withdrawal cap");

        vm.warp(block.timestamp + 1 days);
        beforeAlice = token.balanceOf(ALICE);
        vm.prank(ALICE);
        vault.claimRewards();
        _eq(token.balanceOf(ALICE), beforeAlice + 6 * U);
        _eq(vault.totalClaimableRewards(), 0);
        _assertLedgerSolvent();

        // The actual beneficiary wallets may claim ONLY funded distribution
        // tokens in the splitter, not the depositor's principal.
        vm.prank(OWNER);
        splitter.claim();
        vm.prank(COMPANY);
        splitter.claim();
        _eq(token.balanceOf(OWNER), 60 * U);
        _eq(token.balanceOf(COMPANY), 14 * U);
        _assertLedgerSolvent();
    }

    function testCumulativeWithdrawalExactly24hBoundary() public {
        _deposit(1_000 * U);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        vault.withdrawPrincipal(75 * U);
        vm.prank(ALICE);
        vault.withdrawPrincipal(125 * U);
        _eq(vault.remainingWithdrawalCap(ALICE), 0);
        vm.prank(ALICE);
        (bool ok,) = address(vault).call(
            abi.encodeCall(NexoraProfitVault.withdrawPrincipal, (1 * U))
        );
        require(!ok, "Split transactions bypassed daily cap");
        vm.warp(block.timestamp + 1 days - 1);
        _eq(vault.remainingWithdrawalCap(ALICE), 0);
        vm.warp(block.timestamp + 1);
        _eq(vault.remainingWithdrawalCap(ALICE), 200 * U);
        vm.prank(ALICE);
        vault.withdrawPrincipal(200 * U);
        _eq(vault.totalPrincipal(), 600 * U);
        _eq(vault.WITHDRAWAL_FEE_BPS(), 0);
        _assertLedgerSolvent();
    }

    function testCorporateRecipientsCannotTakeUserPrincipal() public {
        _deposit(1_000 * U);
        vm.warp(block.timestamp + 90 days);
        vm.prank(OWNER);
        (bool ok,) = address(vault).call(
            abi.encodeCall(NexoraProfitVault.withdrawPrincipal, (200 * U))
        );
        require(!ok, "Owner could withdraw other user's capital");
        vm.prank(COMPANY);
        (ok,) = address(vault).call(
            abi.encodeCall(NexoraProfitVault.withdrawPrincipal, (200 * U))
        );
        require(!ok, "Company could withdraw user's capital");
        _assertLedgerSolvent();
    }

    function testReinvestCurrentlyDoesNotTriggerCompanyPayout() public {
        // Another explicit feature gap: Model 2 says both deposits and
        // reinvests should generate up-front company allocations.
        // Existing vault only moves funded reward liabilities to principal.
        _deposit(1_000 * U);
        router.fundAndRoute(1_000 * U, bytes32(uint256(5)));
        vm.warp(block.timestamp + 1 days);
        vault.allocateReward(ALICE, 10 * U, bytes32(uint256(6)));
        uint256 fundedCompanyPoolBefore = splitter.totalFunded();
        uint256 companyClaimBefore = splitter.claimable(COMPANY);
        vm.prank(ALICE);
        vault.reinvestRewards(10 * U);
        _eq(splitter.totalFunded(), fundedCompanyPoolBefore);
        _eq(splitter.claimable(COMPANY), companyClaimBefore);
        _assertLedgerSolvent();
    }

    function testNoNewRewardCreatedByDepositOrTimeAlone() public {
        _deposit(1_000 * U);
        vm.warp(block.timestamp + 365 days);
        _eq(vault.getAccount(ALICE).baseRewards, 0);
        _eq(vault.getAccount(ALICE).referralRewards, 0);
        _eq(vault.totalClaimableRewards(), 0);
        vm.prank(ALICE);
        (bool ok,) = address(vault).call(abi.encodeCall(NexoraProfitVault.claimRewards, ()));
        require(!ok, "Unfunded rewards were claimable");
        _assertLedgerSolvent();
    }

    function testFuzz_AccountingBalancesStayConserved(uint64 rawDeposit, uint64 rawRevenue)
        public
    {
        uint256 amount = (10 + uint256(rawDeposit) % 49_990) * U;
        uint256 funded = (10 + uint256(rawRevenue) % 40_000) * U;
        _deposit(amount);
        router.fundAndRoute(funded, bytes32(uint256(50)));
        _eq(vault.totalPrincipal(), amount);
        _eq(vault.unallocatedRewards(), funded * 80 / 100);
        _eq(splitter.totalClaimable(), funded * 20 / 100);
        _assertLedgerSolvent();
    }

    function testFuzz_FeesAreZeroAndDailyCapEnforced(uint64 raw) public {
        uint256 deposited = (1_000 + uint256(raw) % 40_000) * U;
        _deposit(deposited);
        vm.warp(block.timestamp + 90 days);
        uint256 cap = deposited / 5;
        uint256 firstPart = cap / 3;
        vm.prank(ALICE);
        vault.withdrawPrincipal(firstPart);
        vm.prank(ALICE);
        vault.withdrawPrincipal(cap - firstPart);
        _eq(vault.remainingWithdrawalCap(ALICE), 0);
        vm.prank(ALICE);
        (bool ok,) = address(vault).call(
            abi.encodeCall(NexoraProfitVault.withdrawPrincipal, (1))
        );
        require(!ok, "Withdrawal cap exceeded");
        _eq(vault.WITHDRAWAL_FEE_BPS(), 0);
        _assertLedgerSolvent();
    }
}
