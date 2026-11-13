// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraModel2Vault} from "../src/NexoraModel2Vault.sol";
import {NexoraModel2TestnetFactory} from "../src/NexoraModel2TestnetFactory.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {MockUSDT} from "./MockUSDT.sol";

interface VmNexoraModel2 {
    function prank(address) external;
    function warp(uint256) external;
    function chainId(uint256) external;
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonAddressArray(string calldata json, string calldata key)
        external pure returns (address[] memory);
}

/** End-to-end OFFLINE model-2 tests; no real tokens/signatures or BSC deployment. */
contract NexoraModel2VaultTest {
    VmNexoraModel2 private constant vm =
        VmNexoraModel2(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant U = 1e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CHARLIE = address(0xC0FFEE);
    address private constant ADMIN = address(0xDADA);
    address private constant ALLOCATOR = address(0xACE);

    MockUSDT private token;
    NexoraRevenueSplitter private splitter;
    NexoraModel2Vault private vault;
    address[11] private wallets;

    function setUp() public {
        vm.chainId(97);
        vm.warp(100 days);
        string memory file = vm.readFile("config/beneficiary-wallets.candidate.json");
        address[] memory all = vm.parseJsonAddressArray(file, ".constructorWallets");
        require(all.length == 11, "Missing wallet configuration");
        for (uint256 i; i < 11; ++i) wallets[i] = all[i];

        token = new MockUSDT();
        splitter = new NexoraRevenueSplitter(
            address(token), address(this), address(this), wallets
        );
        vault = new NexoraModel2Vault(
            address(token), ADMIN, address(this), ALLOCATOR, address(splitter)
        );
        splitter.grantRole(splitter.FUNDER_ROLE(), address(vault));
        splitter.revokeRole(splitter.FUNDER_ROLE(), address(this));

        for (uint256 i; i < 3; ++i) {
            address user = i == 0 ? ALICE : (i == 1 ? BOB : CHARLIE);
            token.mint(user, 60_000 * U);
            vm.prank(user);
            token.approve(address(vault), type(uint256).max);
        }
        token.mint(address(this), 1_000_000 * U); // Mock externally funded rewards only
        token.approve(address(vault), type(uint256).max);
    }

    function _deposit(address member, uint256 gross, address referrer) private {
        vm.prank(member);
        vault.deposit(gross, referrer);
    }

    function _eq(uint256 got, uint256 want) private pure {
        require(got == want, "Model2 accounting mismatch");
    }

    function _reverted(address caller, bytes memory callData) private {
        vm.prank(caller);
        (bool ok,) = address(vault).call(callData);
        require(!ok, "Expected Model2 operation to revert");
    }

    function _solvent() private view {
        require(vault.isSolvent(), "Model2 vault liabilities unbacked");
        require(splitter.isSolvent(), "Corporate liabilities unbacked");
        _eq(token.balanceOf(address(vault)),
            vault.totalPrincipal() + vault.unallocatedRewards() +
            vault.totalClaimableRewards());
        _eq(token.balanceOf(address(splitter)), splitter.totalClaimable());
    }

    function testGrossOneThousandNetEightHundredAndAllElevenSharesFunded() public {
        uint256 before = token.balanceOf(ALICE);
        _deposit(ALICE, 1_000 * U, address(0));
        NexoraModel2Vault.Account memory a = vault.getAccount(ALICE);
        _eq(before - token.balanceOf(ALICE), 1_000 * U);
        _eq(a.grossDepositsLifetime, 1_000 * U);
        _eq(a.grossPositionBasis, 1_000 * U);
        _eq(a.principal, 800 * U);
        _eq(vault.totalPrincipal(), 800 * U);
        _eq(vault.externalDepositBasis(ALICE), 1_000 * U);
        _eq(token.balanceOf(address(vault)), 800 * U);
        _eq(token.balanceOf(address(splitter)), 200 * U);
        _eq(splitter.claimable(wallets[0]), 60 * U);
        for (uint256 i = 1; i < 11; ++i) _eq(splitter.claimable(wallets[i]), 14 * U);
        _eq(vault.remainingWithdrawalCap(ALICE), 200 * U);
        _eq(vault.principalTrancheCount(ALICE), 1);
        (uint256 net, uint256 corporate) = vault.previewEntry(1_000 * U);
        _eq(net, 800 * U);
        _eq(corporate, 200 * U);
        _eq(vault.WITHDRAWAL_FEE_BPS(), 0);
        _solvent();
    }

    function testRewardTierAndDailyCapUseOpenGrossPositionNotNetPrincipal() public {
        _deposit(ALICE, 1_000 * U, address(0));
        vm.warp(block.timestamp + 1 days);
        _eq(vault.tierBps(ALICE), 100); // 1% conditional maximum
        vault.fundRewards(10 * U);
        vm.prank(ALLOCATOR);
        vault.allocateReward(ALICE, 10 * U, bytes32(uint256(1)));
        _eq(vault.getAccount(ALICE).baseRewards, 10 * U);
        _eq(vault.getAccount(ALICE).principal, 800 * U);
        _solvent();

        // A separate qualified window is necessary; more than 1% gross
        // cannot be allocated even if the reward reserve is fully funded.
        vault.fundRewards(100 * U);
        vm.warp(block.timestamp + 1 days);
        _reverted(ALLOCATOR, abi.encodeCall(
            NexoraModel2Vault.allocateReward,
            (ALICE, 10 * U + 1, bytes32(uint256(2)))
        ));
        _solvent();
    }

    function testReinvestFundedRewardHundredPercentGrossRecordButOnlyEightyPercentNet() public {
        _deposit(ALICE, 1_000 * U, address(0));
        vault.fundRewards(10 * U);
        vm.warp(block.timestamp + 1 days);
        vm.prank(ALLOCATOR);
        vault.allocateReward(ALICE, 10 * U, bytes32(uint256(10)));
        uint256 tokensBefore = token.balanceOf(address(vault));
        vm.prank(ALICE);
        vault.reinvestRewards(10 * U);

        NexoraModel2Vault.Account memory a = vault.getAccount(ALICE);
        _eq(a.principal, 808 * U);
        _eq(a.grossPositionBasis, 1_010 * U);
        _eq(a.grossDepositsLifetime, 1_000 * U); // reinvest not external deposit
        _eq(vault.externalDepositBasis(ALICE), 1_000 * U);
        _eq(vault.totalClaimableRewards(), 0);
        _eq(vault.principalTrancheCount(ALICE), 2);
        _eq(token.balanceOf(address(vault)), tokensBefore - 2 * U);
        _eq(splitter.claimable(wallets[0]), 60 * U + 6 * U / 10);
        for (uint256 i = 1; i < 11; ++i) {
            _eq(splitter.claimable(wallets[i]), 14 * U + 14 * U / 100);
        }
        _solvent();
    }

    function testCompleteRedemptionReducesGrossPlanBasisToZeroButRetainsDepositHistory() public {
        _deposit(ALICE, 1_000 * U, address(0));
        vm.warp(block.timestamp + 90 days);
        for (uint256 i; i < 4; ++i) {
            vm.prank(ALICE);
            vault.withdrawPrincipal(200 * U);
            NexoraModel2Vault.Account memory account = vault.getAccount(ALICE);
            _eq(account.principal, (600 - i * 200) * U);
            _eq(account.grossPositionBasis, (750 - i * 250) * U);
            _eq(account.grossDepositsLifetime, 1_000 * U);
            _solvent();
            vm.warp(block.timestamp + 1 days);
        }
        _eq(vault.getAccount(ALICE).principal, 0);
        _eq(vault.getAccount(ALICE).grossPositionBasis, 0);
        _eq(vault.tierBps(ALICE), 0);
        _eq(vault.totalPrincipal(), 0);
        _eq(token.balanceOf(address(vault)), 0);
    }

    function testTopUpsGetSeparateMaturitiesAndDailyCapAggregatesGrossDeposits() public {
        _deposit(ALICE, 1_000 * U, address(0));
        vm.warp(block.timestamp + 80 days);
        _deposit(ALICE, 500 * U, address(0));
        _eq(vault.getAccount(ALICE).grossDepositsLifetime, 1_500 * U);
        _eq(vault.getAccount(ALICE).principal, 1_200 * U);
        _eq(vault.remainingWithdrawalCap(ALICE), 300 * U);
        vm.warp(block.timestamp + 10 days);
        vm.prank(ALICE);
        vault.withdrawPrincipal(300 * U); // only original tranche is matured
        _eq(vault.getAccount(ALICE).principal, 900 * U);
        _eq(vault.getAccount(ALICE).grossPositionBasis, 1_125 * U);
        _reverted(ALICE, abi.encodeCall(NexoraModel2Vault.withdrawPrincipal, (1 * U)));
        vm.warp(block.timestamp + 1 days);
        vm.prank(ALICE);
        vault.withdrawPrincipal(300 * U);
        vm.warp(block.timestamp + 1 days);
        // The remaining original net principal is 200 U, and the 400 U
        // from the newer deposit is still time-locked.
        _reverted(ALICE, abi.encodeCall(NexoraModel2Vault.withdrawPrincipal, (300 * U)));
        vm.prank(ALICE);
        vault.withdrawPrincipal(200 * U);
        _solvent();
    }

    function testExplicitFeeIsNotReappliedOnWithdrawal() public {
        _deposit(ALICE, 1_000 * U, address(0));
        vm.warp(block.timestamp + 90 days);
        uint256 balanceBefore = token.balanceOf(ALICE);
        vm.prank(ALICE);
        vault.withdrawPrincipal(200 * U);
        _eq(token.balanceOf(ALICE), balanceBefore + 200 * U);
        _eq(vault.WITHDRAWAL_FEE_BPS(), 0);
        _solvent();
    }

    function testDepositsRevertAtomicallyIfSplitterFundingRoleMissing() public {
        splitter.revokeRole(splitter.FUNDER_ROLE(), address(vault));
        uint256 userBefore = token.balanceOf(ALICE);
        _reverted(ALICE, abi.encodeCall(
            NexoraModel2Vault.deposit, (1_000 * U, address(0))
        ));
        _eq(token.balanceOf(ALICE), userBefore);
        _eq(token.balanceOf(address(vault)), 0);
        _eq(token.balanceOf(address(splitter)), 0);
        _eq(vault.getAccount(ALICE).principal, 0);
        _eq(vault.getAccount(ALICE).grossDepositsLifetime, 0);
        _eq(vault.distributionNonce(), 0);
        _solvent();
    }

    function testReinvestRevertsAtomicallyIfSplitterFundingRoleMissing() public {
        _deposit(ALICE, 1_000 * U, address(0));
        vault.fundRewards(10 * U);
        vm.warp(block.timestamp + 1 days);
        vm.prank(ALLOCATOR);
        vault.allocateReward(ALICE, 10 * U, bytes32(uint256(13)));
        splitter.revokeRole(splitter.FUNDER_ROLE(), address(vault));
        uint256 balanceBefore = token.balanceOf(address(vault));
        _reverted(ALICE, abi.encodeCall(NexoraModel2Vault.reinvestRewards, (10 * U)));
        _eq(token.balanceOf(address(vault)), balanceBefore);
        _eq(vault.getAccount(ALICE).baseRewards, 10 * U);
        _eq(vault.getAccount(ALICE).principal, 800 * U);
        _solvent();
    }

    function testOnlyDepositorCanWithdrawAndBeneficiariesCannotMoveUserPrincipal() public {
        _deposit(ALICE, 1_000 * U, address(0));
        vm.warp(block.timestamp + 90 days);
        _reverted(wallets[0], abi.encodeCall(
            NexoraModel2Vault.withdrawPrincipal, (200 * U)
        ));
        for (uint256 i = 1; i < 11; ++i) {
            _reverted(wallets[i], abi.encodeCall(
                NexoraModel2Vault.withdrawPrincipal, (200 * U)
            ));
        }
        _eq(vault.getAccount(ALICE).principal, 800 * U);
        _solvent();
    }

    function testHundredTestAccountsFullDepositShareConservation() public {
        for (uint256 i; i < 100; ++i) {
            address member = address(uint160(0xAB1000 + i));
            token.mint(member, 1_000 * U);
            vm.prank(member);
            token.approve(address(vault), type(uint256).max);
            vm.prank(member);
            vault.deposit(1_000 * U, address(0));
            _eq(vault.getAccount(member).grossDepositsLifetime, 1_000 * U);
            _eq(vault.getAccount(member).principal, 800 * U);
        }
        _eq(vault.totalPrincipal(), 80_000 * U);
        _eq(token.balanceOf(address(vault)), 80_000 * U);
        _eq(splitter.totalClaimable(), 20_000 * U);
        _eq(splitter.claimable(wallets[0]), 6_000 * U);
        for (uint256 i = 1; i < 11; ++i) {
            _eq(splitter.claimable(wallets[i]), 1_400 * U);
        }
        _eq(vault.distributionNonce(), 100);
        _solvent();
    }

    function testFuzz_AnyGrossWithinCapitalLimitBalancesExactly(uint96 raw) public {
        uint256 gross = (10 * U) + uint256(raw) % (49_990 * U);
        _deposit(ALICE, gross, address(0));
        uint256 fee = gross / 5;
        uint256 net = gross - fee;
        _eq(vault.getAccount(ALICE).grossDepositsLifetime, gross);
        _eq(vault.getAccount(ALICE).grossPositionBasis, gross);
        _eq(vault.getAccount(ALICE).principal, net);
        _eq(splitter.totalClaimable(), fee);
        _eq(splitter.totalFunded(), fee);
        _eq(token.balanceOf(address(vault)), net);
        _eq(token.balanceOf(address(splitter)), fee);
        _eq(splitter.claimable(wallets[0]) + 10 * splitter.claimable(wallets[1]), fee);
        _solvent();
    }

    function testFuzz_PartialWithdrawalReducesGrossBasisProportionately(uint96 raw) public {
        _deposit(ALICE, 1_000 * U, address(0));
        vm.warp(block.timestamp + 90 days);
        uint256 amount = 1 + uint256(raw) % (200 * U);
        vm.prank(ALICE);
        vault.withdrawPrincipal(amount);
        NexoraModel2Vault.Account memory a = vault.getAccount(ALICE);
        _eq(a.principal, 800 * U - amount);
        require(a.grossPositionBasis <= 1_000 * U &&
                a.grossPositionBasis >= a.principal,
                "Gross and net principal diverged");
        _eq(a.grossDepositsLifetime, 1_000 * U);
        _solvent();
    }

    function testTestnetFactoryRoleHandoffAndMainnetChainGuard() public {
        // Admin/allocator/funder must be distinct; factory is intentionally
        // CHAIN-97 ONLY until independent audit and governance sign-off.
        NexoraModel2TestnetFactory system = new NexoraModel2TestnetFactory(
            address(token), ADMIN, address(this), ALLOCATOR, wallets
        );
        NexoraModel2Vault created = system.vault();
        NexoraRevenueSplitter company = system.splitter();
        require(company.hasRole(company.FUNDER_ROLE(), address(created)),
            "Vault must fund splitter from deposit or reinvest only");
        require(!company.hasRole(company.FUNDER_ROLE(), address(system)),
            "Factory must not retain funding role");
        require(!company.hasRole(company.DEFAULT_ADMIN_ROLE(), address(system)),
            "Factory must not retain admin role");
        require(!created.hasRole(created.DEFAULT_ADMIN_ROLE(), address(system)),
            "Factory must not retain capital admin role");
        require(company.hasRole(company.DEFAULT_ADMIN_ROLE(), ADMIN),
            "Company splitter not owned by governance");
        require(created.hasRole(created.DEFAULT_ADMIN_ROLE(), ADMIN),
            "Vault not owned by governance");

        vm.chainId(56);
        bool reverted;
        try new NexoraModel2TestnetFactory(
            address(token), ADMIN, address(this), ALLOCATOR, wallets
        ) returns (NexoraModel2TestnetFactory) {} catch { reverted = true; }
        require(reverted, "Unsafe testnet factory could deploy on mainnet");
    }
}
