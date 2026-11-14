// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraModel2Vault} from "../src/NexoraModel2Vault.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {NexoraModel2TestnetFactory} from "../src/NexoraModel2TestnetFactory.sol";
import {NexoraTestUSDT} from "../src/NexoraTestUSDT.sol";
import {MockUSDT} from "./MockUSDT.sol";

interface VmDeepNexora {
    function warp(uint256) external;
    function prank(address) external;
    function chainId(uint256) external;
    function getBlockTimestamp() external view returns (uint256);
    function readFile(string calldata) external view returns (string memory);
    function parseJsonAddressArray(string calldata, string calldata) external pure returns (address[] memory);
}

/** LOCAL MOCK-TOKEN TESTS. Passing these is NOT audit or mainnet authorization. */
abstract contract Model2DeepFixture {
    VmDeepNexora internal constant vm = VmDeepNexora(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant U = 1e18;
    uint256 internal constant T = 1_800_000_000;
    address internal constant A = address(0xA001);
    address internal constant B = address(0xB001);
    address internal constant C = address(0xC001);
    address internal constant D = address(0xD001);
    address internal constant STRANGER = address(0xBAD);
    MockUSDT internal token;
    NexoraRevenueSplitter internal splitter;
    NexoraModel2Vault internal vault;
    address[11] internal beneficiaries;
    address[] internal actors;
    mapping(address => bool) internal seen;

    function setUp() public virtual {
        vm.chainId(97); vm.warp(T);
        address[] memory supplied = vm.parseJsonAddressArray(vm.readFile("config/beneficiary-wallets.candidate.json"), ".constructorWallets");
        require(supplied.length == 11, "manifest length");
        for (uint256 i; i < 11; ++i) beneficiaries[i] = supplied[i];
        token = new MockUSDT();
        splitter = new NexoraRevenueSplitter(address(token), address(this), address(this), beneficiaries);
        vault = new NexoraModel2Vault(address(token), address(this), address(this), address(this), address(splitter));
        splitter.grantRole(splitter.FUNDER_ROLE(), address(vault));
        splitter.revokeRole(splitter.FUNDER_ROLE(), address(this));
        token.mint(address(this), 2_000_000 * U);
        token.approve(address(vault), type(uint256).max);
    }
    function eq(uint256 got, uint256 want) internal pure { require(got == want, "amount mismatch"); }
    function seed(address who, uint256 gross, address parent) internal {
        if (!seen[who]) { actors.push(who); seen[who] = true; }
        token.mint(who, gross);
        vm.prank(who); token.approve(address(vault), type(uint256).max);
        vm.prank(who); vault.deposit(gross, parent);
    }
    function reject(address who, bytes memory data, bytes4 selector) internal {
        vm.prank(who); (bool ok, bytes memory reason) = address(vault).call(data);
        require(!ok && reason.length >= 4, "expected typed revert");
        bytes4 got; assembly { got := mload(add(reason, 32)) }
        require(got == selector, "unexpected revert selector");
    }
    function checkLedgers() internal view {
        uint256 net; uint256 rewards;
        for (uint256 i; i < actors.length; ++i) {
            NexoraModel2Vault.Account memory a = vault.getAccount(actors[i]);
            net += a.principal; rewards += a.baseRewards + a.referralRewards;
            uint256 tn; uint256 tg;
            for (uint256 j; j < vault.principalTrancheCount(actors[i]); ++j) {
                (uint256 remaining,) = vault.principalTrancheAt(actors[i], j);
                tn += remaining; tg += vault.principalTrancheGrossAt(actors[i], j);
            }
            eq(tn, a.principal); eq(tg, a.grossPositionBasis);
        }
        eq(net, vault.totalPrincipal()); eq(rewards, vault.totalClaimableRewards());
        require(vault.isSolvent() && splitter.isSolvent(), "insolvent");
        require(token.balanceOf(address(vault)) >= net + rewards + vault.unallocatedRewards(), "underbacked");
        uint256 corporate;
        for (uint256 i; i < 11; ++i) corporate += splitter.claimable(beneficiaries[i]);
        eq(corporate, splitter.totalClaimable());
        eq(token.allowance(address(vault), address(splitter)), 0);
    }
}

contract NexoraModel2DeepValidationTest is Model2DeepFixture {
    function testAllFiveVipLevelsUseGrossEligibleCapitalAndBalancedTeams() public {
        uint256[5] memory capitals = [uint256(10), 500, 2500, 10000, 25000];
        uint256[5] memory directs = [uint256(0), 2, 4, 6, 10];
        uint256[5] memory team = [uint256(0), 2500, 12500, 50000, 125000];
        uint256[5] memory rates = [uint256(100), 125, 150, 200, 250];
        for (uint256 i; i < 5; ++i) {
            address root = address(uint160(0x1000 + i)); seed(root, capitals[i] * U, address(0));
            for (uint256 j; j < directs[i]; ++j) seed(address(uint160(0x2000 + i * 20 + j)), (team[i] * U + directs[i] - 1) / directs[i], root);
        }
        vm.warp(T + 1 days);
        for (uint256 i; i < 5; ++i) {
            address root = address(uint160(0x1000 + i));
            for (uint256 j; j < directs[i]; ++j) vault.syncDirect(address(uint160(0x2000 + i * 20 + j)));
            eq(vault.tierBps(root), rates[i]); eq(vault.getAccount(root).activeDirects, directs[i]);
        }
        checkLedgers();
    }
    function testDominantBranchBlocksPromotionDespiteCapitalAndActiveDirects() public {
        seed(A, 500 * U, address(0)); seed(B, 2000 * U, A); seed(C, 500 * U, A);
        vm.warp(T + 1 days); vault.syncDirect(B); vault.syncDirect(C);
        eq(vault.teamVolume(A), 2500 * U); eq(vault.tierBps(A), 100);
    }
    function testBalancedBranchBoundaryAndTopUpEligibilityReset() public {
        seed(A, 500 * U, address(0)); seed(B, 1250 * U, A); seed(C, 1250 * U, A);
        vm.warp(T + 1 days); vault.syncDirect(B); vault.syncDirect(C); eq(vault.tierBps(A), 125);
        seed(B, 1, A); eq(vault.getAccount(A).activeDirects, 1);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.syncDirect, (B)), NexoraModel2Vault.NotMature.selector);
        vm.warp(T + 2 days); vault.syncDirect(B);
        eq(vault.getAccount(A).activeDirects, 2); eq(vault.tierBps(A), 100); checkLedgers();
    }
    function testThreeLevelReferralCostsAreFullyReservedBeforeCredit() public {
        seed(A, 100 * U, address(0)); seed(B, 100 * U, A); seed(C, 100 * U, B); seed(D, 100 * U, C);
        vm.warp(T + 1 days); vault.fundRewards(125 * U / 100); vault.allocateReward(D, U, bytes32(uint256(1)));
        eq(vault.getAccount(D).baseRewards, U); eq(vault.getAccount(C).referralRewards, 15 * U / 100);
        eq(vault.getAccount(B).referralRewards, 7 * U / 100); eq(vault.getAccount(A).referralRewards, 3 * U / 100);
        eq(vault.unallocatedRewards(), 0); eq(vault.totalClaimableRewards(), 125 * U / 100); checkLedgers();
    }
    function testInactiveMiddleAncestorIsSkippedWithoutCompressingReferralLevels() public {
        seed(A, 100 * U, address(0)); seed(B, 10 * U, A); seed(C, 100 * U, B); seed(D, 100 * U, C);
        vm.warp(T + 1 days); vault.fundRewards(118 * U / 100); vault.allocateReward(D, U, bytes32(uint256(2)));
        eq(vault.getAccount(C).referralRewards, 15 * U / 100); eq(vault.getAccount(B).referralRewards, 0);
        eq(vault.getAccount(A).referralRewards, 3 * U / 100); eq(vault.totalClaimableRewards(), 118 * U / 100); checkLedgers();
    }
    function testReferralVolumeTracksOnlyThreeLevelsAndRedemptionsReduceIt() public {
        seed(A, 100 * U, address(0)); seed(B, 100 * U, A); seed(C, 100 * U, B); seed(D, 100 * U, C);
        address fifth = address(0xE001); seed(fifth, 100 * U, D);
        eq(vault.teamVolume(A), 300 * U); eq(vault.teamVolume(B), 300 * U);
        eq(vault.teamVolume(C), 200 * U); eq(vault.teamVolume(D), 100 * U);
        vm.warp(T + 90 days); vm.prank(fifth); vault.withdrawPrincipal(20 * U);
        eq(vault.teamVolume(A), 300 * U); eq(vault.teamVolume(B), 275 * U); eq(vault.teamVolume(C), 175 * U);
        eq(vault.branchVolume(B, C), 275 * U); checkLedgers();
    }
    function testWithdrawalBelowActiveThresholdUpdatesParentImmediately() public {
        seed(A, 100 * U, address(0)); seed(B, 125 * U, A);
        vm.warp(T + 1 days); vault.syncDirect(B); eq(vault.getAccount(A).activeDirects, 1);
        vm.warp(T + 90 days); vm.prank(B); vault.withdrawPrincipal(25 * U);
        eq(vault.getAccount(A).activeDirects, 0);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.syncDirect, (B)), NexoraModel2Vault.NotEligible.selector); checkLedgers();
    }
    function testReferrerRulesRejectSelfFutureMemberAndChanges() public {
        reject(A, abi.encodeCall(NexoraModel2Vault.deposit, (10 * U, A)), NexoraModel2Vault.InvalidReferrer.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.deposit, (10 * U, B)), NexoraModel2Vault.InvalidReferrer.selector);
        seed(A, 100 * U, address(0)); seed(B, 100 * U, A); seed(C, 100 * U, address(0));
        reject(B, abi.encodeCall(NexoraModel2Vault.deposit, (U, C)), NexoraModel2Vault.InvalidReferrer.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.deposit, (U, B)), NexoraModel2Vault.InvalidReferrer.selector);
        eq(vault.directCount(A), 1); require(vault.directAt(A, 0) == B, "wrong child");
    }
    function testMaximum128DirectsAnd129thRejectedExplicitly() public {
        seed(A, 500 * U, address(0));
        for (uint256 i; i < 128; ++i) seed(address(uint160(0x4000 + i)), 100 * U, A);
        eq(vault.directCount(A), 128);
        reject(address(0x9000), abi.encodeCall(NexoraModel2Vault.deposit, (100 * U, A)), NexoraModel2Vault.TooManyDirects.selector);
        vm.warp(T + 1 days);
        for (uint256 i; i < 128; ++i) vault.syncDirect(address(uint160(0x4000 + i)));
        eq(vault.getAccount(A).activeDirects, 128); eq(vault.tierBps(A), 125); checkLedgers();
    }
    function testMinimumMaximumGrossCapitalAndZeroInputs() public {
        reject(A, abi.encodeCall(NexoraModel2Vault.deposit, (0, address(0))), NexoraModel2Vault.InvalidAmount.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.deposit, (10 * U - 1, address(0))), NexoraModel2Vault.InvalidAmount.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.deposit, (50_000 * U + 1, address(0))), NexoraModel2Vault.ExceedsCapitalLimit.selector);
        seed(A, 10 * U, address(0)); seed(B, 50_000 * U, address(0));
        eq(vault.getAccount(A).principal, 8 * U); eq(vault.getAccount(B).principal, 40_000 * U);
        reject(B, abi.encodeCall(NexoraModel2Vault.deposit, (1, address(0))), NexoraModel2Vault.ExceedsCapitalLimit.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.withdrawPrincipal, (0)), NexoraModel2Vault.InvalidAmount.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.withdrawPrincipal, (9 * U)), NexoraModel2Vault.InsufficientPrincipal.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.reinvestRewards, (0)), NexoraModel2Vault.InvalidAmount.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.reinvestRewards, (1)), NexoraModel2Vault.InvalidAmount.selector);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.fundRewards, (0)), NexoraModel2Vault.InvalidAmount.selector);
    }
    function testNoRewardFromDepositsDonationOrTimeAlone() public {
        seed(A, 1000 * U, address(0)); token.transfer(address(vault), 500 * U); vm.warp(T + 365 days);
        eq(vault.unallocatedRewards(), 0);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.allocateReward, (A, U, bytes32(uint256(3)))), NexoraModel2Vault.InsufficientRewardPool.selector);
        reject(A, abi.encodeCall(NexoraModel2Vault.claimRewards, ()), NexoraModel2Vault.InvalidAmount.selector);
        require(!vault.usedReportIds(bytes32(uint256(3))), "failed allocation marked used"); checkLedgers();
    }
    function testReportReplayCooldownAndBoundaryAreEnforced() public {
        seed(A, 1000 * U, address(0)); vault.fundRewards(100 * U);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.allocateReward, (A, U, bytes32(uint256(4)))), NexoraModel2Vault.NotEligible.selector);
        vm.warp(T + 1 days);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.allocateReward, (A, U, bytes32(0))), NexoraModel2Vault.InvalidOrUsedReport.selector);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.allocateReward, (A, 10 * U + 1, bytes32(uint256(4)))), NexoraModel2Vault.ExceedsDailyCap.selector);
        vault.allocateReward(A, 10 * U, bytes32(uint256(4)));
        reject(address(this), abi.encodeCall(NexoraModel2Vault.allocateReward, (A, U, bytes32(uint256(4)))), NexoraModel2Vault.InvalidOrUsedReport.selector);
        vm.warp(T + 2 days - 1);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.allocateReward, (A, U, bytes32(uint256(5)))), NexoraModel2Vault.CreditTooSoon.selector);
        vm.warp(T + 2 days); vault.allocateReward(A, U, bytes32(uint256(5))); checkLedgers();
    }
    function testRewardClaimClipsAtSharedDailyLimitAndPreservesResidual() public {
        seed(A, 1000 * U, address(0)); vault.fundRewards(210 * U);
        for (uint256 i; i < 21; ++i) { vm.warp(T + (i + 1) * 1 days); vault.allocateReward(A, 10 * U, bytes32(i + 100)); }
        vm.warp(T + 90 days - 1);
        reject(A, abi.encodeCall(NexoraModel2Vault.claimRewards, ()), NexoraModel2Vault.NotMature.selector);
        vm.warp(T + 90 days); vm.prank(A); eq(vault.claimRewards(), 200 * U);
        eq(vault.getAccount(A).baseRewards, 10 * U);
        reject(A, abi.encodeCall(NexoraModel2Vault.claimRewards, ()), NexoraModel2Vault.WithdrawalLimitExceeded.selector);
        vm.warp(T + 91 days); vm.prank(A); eq(vault.claimRewards(), 10 * U);
        eq(vault.remainingWithdrawalCap(A), 190 * U); checkLedgers();
    }
    function testReinvestConsumesBaseThenReferralWithoutDuplicatingLiabilities() public {
        seed(A, 100 * U, address(0)); seed(B, 100 * U, A); vault.fundRewards(3 * U); vm.warp(T + 1 days);
        vault.allocateReward(A, U, bytes32(uint256(200))); vault.allocateReward(B, U, bytes32(uint256(201)));
        eq(vault.getAccount(A).referralRewards, 15 * U / 100);
        vm.prank(A); vault.reinvestRewards(110 * U / 100);
        eq(vault.getAccount(A).baseRewards, 0); eq(vault.getAccount(A).referralRewards, 5 * U / 100);
        eq(vault.getAccount(A).principal, 80 * U + 88 * U / 100);
        eq(vault.getAccount(A).grossDepositsLifetime, 100 * U); checkLedgers();
    }
    function testPauseBlocksNewRiskButMaturedPrincipalAndRewardRemainClaimable() public {
        seed(A, 1000 * U, address(0)); vault.fundRewards(10 * U);
        vm.warp(T + 1 days); vault.allocateReward(A, 10 * U, bytes32(uint256(202))); vault.pause();
        bytes4 paused = bytes4(keccak256("EnforcedPause()"));
        reject(A, abi.encodeCall(NexoraModel2Vault.deposit, (U, address(0))), paused);
        reject(A, abi.encodeCall(NexoraModel2Vault.reinvestRewards, (U)), paused);
        reject(address(this), abi.encodeCall(NexoraModel2Vault.allocateReward, (A, U, bytes32(uint256(203)))), paused);
        vm.warp(T + 90 days); vm.prank(A); vault.withdrawPrincipal(190 * U);
        vm.prank(A); vault.claimRewards(); eq(vault.remainingWithdrawalCap(A), 0);
        vault.unpause(); seed(A, 10 * U, address(0)); checkLedgers();
    }
    function testPausedSplitterRevertsEntireNewEntryButCannotStopExistingExit() public {
        seed(A, 1000 * U, address(0));
        // Fund the attempted top-up so rejection occurs at the paused splitter,
        // not earlier at the ERC20 insufficient-balance check.
        token.mint(A, U); splitter.pause();
        reject(A, abi.encodeCall(NexoraModel2Vault.deposit, (U, address(0))), bytes4(keccak256("EnforcedPause()")));
        eq(token.balanceOf(A), U); eq(vault.getAccount(A).grossDepositsLifetime, 1000 * U);
        vm.warp(T + 90 days); vm.prank(A); vault.withdrawPrincipal(200 * U);
        vm.prank(beneficiaries[0]); splitter.claim(); splitter.unpause(); checkLedgers();
    }
    function testUnauthorizedFundingAllocationPauseAndUnpauseRejected() public {
        bytes4 access = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        reject(STRANGER, abi.encodeCall(NexoraModel2Vault.fundRewards, (U)), access);
        reject(STRANGER, abi.encodeCall(NexoraModel2Vault.allocateReward, (A, U, bytes32(uint256(204)))), access);
        reject(STRANGER, abi.encodeCall(NexoraModel2Vault.pause, ()), access);
        vault.pause(); reject(STRANGER, abi.encodeCall(NexoraModel2Vault.unpause, ()), access); vault.unpause();
    }
    function testReadOnlySnapshotDistinguishesGrossNetRewardsAndCapacityNotLiquidity() public {
        seed(A, 1000 * U, address(0));
        (uint256 gross, uint256 basis, uint256 net, uint256 reward, uint256 cap) = vault.accountSnapshot(A);
        eq(gross, 1000 * U); eq(basis, 1000 * U); eq(net, 800 * U); eq(reward, 0); eq(cap, 200 * U);
        reject(A, abi.encodeCall(NexoraModel2Vault.withdrawPrincipal, (U)), NexoraModel2Vault.NoMaturedTranche.selector);
        (gross, basis, net, reward, cap) = vault.accountSnapshot(STRANGER); eq(gross + basis + net + reward + cap, 0);
    }
    function testTinyTopUpDoesNotPayMoreThanActualReceivedTokens() public {
        seed(A, 1000 * U, address(0)); uint256 nonce = vault.distributionNonce(); seed(A, 1, address(0));
        eq(vault.distributionNonce(), nonce); eq(vault.getAccount(A).principal, 800 * U + 1);
        eq(vault.getAccount(A).grossPositionBasis, 1000 * U + 1); checkLedgers();
    }
    function testTestTokenMintRestrictedAndFactoryBadRolesOrChainsRejected() public {
        NexoraTestUSDT testAsset = new NexoraTestUSDT(address(this)); vm.prank(STRANGER);
        (bool ok,) = address(testAsset).call(abi.encodeCall(NexoraTestUSDT.mintTestTokens, (A, U)));
        require(!ok, "unauthorized faucet mint"); testAsset.mintTestTokens(A, U); eq(testAsset.balanceOf(A), U);
        bool created;
        try new NexoraModel2TestnetFactory(address(token), address(0), B, C, beneficiaries) { created = true; } catch {}
        require(!created, "zero role accepted");
        try new NexoraModel2TestnetFactory(address(token), A, A, C, beneficiaries) { created = true; } catch {}
        require(!created, "role collision accepted"); vm.chainId(1);
        try new NexoraModel2TestnetFactory(address(token), A, B, C, beneficiaries) { created = true; } catch {}
        require(!created, "wrong chain accepted");
    }
    function testHundredAccountsCompleteDepositRewardReinvestAndFullExitLifecycle() public {
        for (uint256 i; i < 100; ++i) seed(address(uint160(0x10000 + i)), 1000 * U, address(0));
        vault.fundRewards(1000 * U); vm.warp(T + 1 days);
        for (uint256 i; i < 100; ++i) {
            address who = address(uint160(0x10000 + i)); vault.allocateReward(who, 10 * U, bytes32(i + 1000));
            vm.prank(who); vault.reinvestRewards(5 * U);
        }
        eq(vault.totalPrincipal(), 80400 * U); eq(vault.totalClaimableRewards(), 500 * U);
        eq(splitter.totalClaimable(), 20100 * U); checkLedgers();
        for (uint256 day; day < 5; ++day) {
            vm.warp(T + (90 + day) * 1 days);
            for (uint256 i; i < 100; ++i) {
                address who = address(uint160(0x10000 + i)); vm.prank(who); vault.withdrawPrincipal(day == 4 ? 4 * U : 200 * U);
                if (day == 4) { vm.prank(who); vault.claimRewards(); }
            }
            checkLedgers();
        }
        eq(vault.totalPrincipal(), 0); eq(vault.totalClaimableRewards(), 0); eq(token.balanceOf(address(vault)), 0);
        eq(splitter.claimable(beneficiaries[0]), 6030 * U);
        for (uint256 j = 1; j < 11; ++j) eq(splitter.claimable(beneficiaries[j]), 1407 * U);
        for (uint256 i; i < 100; ++i) {
            address who = address(uint160(0x10000 + i)); eq(token.balanceOf(who), 809 * U);
            eq(vault.getAccount(who).grossPositionBasis, 0); eq(vault.getAccount(who).grossDepositsLifetime, 1000 * U);
        }
    }
}

contract NexoraModel2RollingRegressionTest is Model2DeepFixture {
    function testRollingWindowRejectsReproducedNear40PercentBoundaryBypass() public {
        seed(A, 1000 * U, address(0));
        vm.warp(T + 90 days); vm.prank(A); vault.withdrawPrincipal(1);
        vm.warp(T + 91 days - 1); vm.prank(A); vault.withdrawPrincipal(200 * U - 1);
        vm.warp(T + 91 days);
        eq(vault.remainingWithdrawalCap(A), 1);
        reject(A, abi.encodeCall(NexoraModel2Vault.withdrawPrincipal, (200 * U)), NexoraModel2Vault.WithdrawalLimitExceeded.selector);
        vm.prank(A); vault.withdrawPrincipal(1);
        eq(vault.withdrawnInLast24Hours(A), 200 * U); eq(vault.remainingWithdrawalCap(A), 0);
        vm.warp(T + 92 days - 1); eq(vault.remainingWithdrawalCap(A), 200 * U - 1);
        checkLedgers();
    }
    function testRollingCapacityExpiresEachWithdrawalIndividually() public {
        seed(A, 1000 * U, address(0));
        vm.warp(T + 90 days); vm.prank(A); vault.withdrawPrincipal(75 * U);
        vm.warp(T + 90 days + 12 hours); vm.prank(A); vault.withdrawPrincipal(125 * U);
        vm.warp(T + 91 days - 1); eq(vault.remainingWithdrawalCap(A), 0);
        vm.warp(T + 91 days); eq(vault.remainingWithdrawalCap(A), 75 * U);
        (uint64 start, uint256 spent) = vault.withdrawalWindows(A);
        eq(start, T + 90 days); eq(spent, 125 * U);
        vm.warp(T + 91 days + 12 hours); eq(vault.remainingWithdrawalCap(A), 200 * U);
    }
    function testSameTimestampWithdrawalsShareCheckpointAndAggregateUsage() public {
        seed(A, 1000 * U, address(0)); vm.warp(T + 90 days);
        vm.prank(A); vault.withdrawPrincipal(50 * U);
        vm.prank(A); vault.withdrawPrincipal(150 * U);
        eq(vault.withdrawalCheckpointCount(A), 1); eq(vault.withdrawnInLast24Hours(A), 200 * U);
        vm.warp(T + 91 days); vm.prank(A); vault.withdrawPrincipal(1);
        eq(vault.withdrawalCheckpointCount(A), 2); checkLedgers();
    }
    function testFuzz_RollingCapMatchesIndependentLinearReference(uint256 randomSeed) public {
        seed(A, 1000 * U, address(0));
        uint256[64] memory stamps;
        uint256[64] memory amounts;
        uint256 now_ = T + 90 days;
        uint256 count;
        for (uint256 step; step < 64; ++step) {
            randomSeed = uint256(keccak256(abi.encode(randomSeed, step)));
            now_ += randomSeed % (6 hours + 1);
            vm.warp(now_);
            uint256 rollingSpent;
            for (uint256 i; i < count; ++i) if (stamps[i] > now_ - 1 days) rollingSpent += amounts[i];
            eq(vault.withdrawnInLast24Hours(A), rollingSpent);
            uint256 expected = 200 * U - rollingSpent;
            eq(vault.remainingWithdrawalCap(A), expected);
            uint256 remainingNet = vault.getAccount(A).principal;
            uint256 maximum = remainingNet < expected ? remainingNet : expected;
            if (maximum != 0) {
                uint256 amount = 1 + (randomSeed >> 32) % maximum;
                vm.prank(A); vault.withdrawPrincipal(amount);
                stamps[count] = now_; amounts[count++] = amount;
            }
            require(vault.withdrawnInLast24Hours(A) <= 200 * U, "rolling cap violated");
        }
        checkLedgers();
    }
}
