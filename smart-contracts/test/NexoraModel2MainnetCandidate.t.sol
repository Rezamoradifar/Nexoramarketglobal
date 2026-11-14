// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraModel2Core} from "../src/NexoraModel2Core.sol";
import {NexoraModel2MainnetVault} from "../src/NexoraModel2MainnetVault.sol";
import {NexoraModel2MainnetFactory} from "../src/NexoraModel2MainnetFactory.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {MockUSDT} from "./MockUSDT.sol";
import {SixDecimalTokenNexora} from "./NexoraAdversarialToken.t.sol";

interface VmMainnetCandidate {
    function chainId(uint256) external;
    function warp(uint256) external;
    function prank(address) external;
    function etch(address, bytes calldata) external;
    function getNonce(address) external view returns (uint64);
    function computeCreateAddress(address, uint256) external pure returns (address);
}

/** Local chain-56 simulation with mock bytecode. No network or real assets. */
contract NexoraModel2MainnetCandidateTest {
    VmMainnetCandidate private constant vm = VmMainnetCandidate(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address private constant ADMIN = address(0xA01);
    address private constant FUNDER = address(0xA02);
    address private constant ALLOCATOR = address(0xA03);
    address private constant ALICE = address(0xA04);
    uint256 private constant U = 1e18;
    uint256 private constant T = 1_800_000_000;
    address[11] private wallets;
    MockUSDT private token;

    function setUp() public {
        vm.chainId(56); vm.warp(T);
        for (uint256 i; i < 11; ++i) wallets[i] = address(uint160(0xB100 + i));
        MockUSDT mock = new MockUSDT();
        vm.etch(USDT, address(mock).code);
        token = MockUSDT(USDT);
    }

    function testPinnedChainAndTokenBootstrapAndRoleHandoff() public {
        NexoraModel2MainnetFactory f = new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, wallets);
        NexoraModel2MainnetVault v = f.vault();
        NexoraRevenueSplitter s = f.splitter();
        require(address(v.asset()) == USDT && address(s.asset()) == USDT, "wrong token");
        require(v.MAINNET_CHAIN_ID() == 56 && v.BSC_USDT() == USDT, "wrong network configuration");
        require(v.hasRole(v.DEFAULT_ADMIN_ROLE(), ADMIN) && v.hasRole(v.GUARDIAN_ROLE(), ADMIN), "missing admin roles");
        require(v.hasRole(v.FUNDER_ROLE(), FUNDER) && v.hasRole(v.ALLOCATOR_ROLE(), ALLOCATOR), "missing operators");
        require(s.hasRole(s.FUNDER_ROLE(), address(v)) && s.hasRole(s.DEFAULT_ADMIN_ROLE(), ADMIN), "bad splitter handoff");
        require(!v.hasRole(v.DEFAULT_ADMIN_ROLE(), address(f)) && !s.hasRole(s.DEFAULT_ADMIN_ROLE(), address(f)), "factory retained admin");
        require(!s.hasRole(s.FUNDER_ROLE(), address(f)) && !s.hasRole(s.GUARDIAN_ROLE(), address(f)), "factory retained roles");
    }

    function testNonMainnetRejectedByVaultAndFactory() public {
        NexoraRevenueSplitter s = new NexoraRevenueSplitter(USDT, address(this), address(this), wallets);
        uint256[2] memory chains = [uint256(97), uint256(31337)];
        for (uint256 i; i < chains.length; ++i) {
            vm.chainId(chains[i]);
            try new NexoraModel2MainnetVault(ADMIN, FUNDER, ALLOCATOR, address(s)) { revert("wrong chain accepted"); }
            catch (bytes memory reason) { require(bytes4(reason) == NexoraModel2Core.MainnetOnly.selector, "wrong vault revert"); }
            try new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, wallets) { revert("wrong factory chain accepted"); }
            catch (bytes memory reason) { require(bytes4(reason) == NexoraModel2MainnetFactory.MainnetOnly.selector, "wrong factory revert"); }
        }
    }

    function testRejectsMissingOrWrongDecimalCanonicalToken() public {
        vm.etch(USDT, "");
        try new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, wallets) { revert("missing token accepted"); }
        catch {}
        SixDecimalTokenNexora bad = new SixDecimalTokenNexora();
        vm.etch(USDT, address(bad).code);
        try new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, wallets) { revert("wrong decimals accepted"); }
        catch {}
    }

    function testRejectsDuplicateBeneficiariesAndZeroRoles() public {
        address[11] memory duplicate = wallets;
        duplicate[10] = duplicate[0];
        try new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, duplicate) { revert("duplicate accepted"); }
        catch {}
        try new NexoraModel2MainnetFactory(address(0), FUNDER, ALLOCATOR, wallets) { revert("zero admin accepted"); }
        catch {}
        try new NexoraModel2MainnetFactory(ADMIN, address(0), ALLOCATOR, wallets) { revert("zero funder accepted"); }
        catch {}
        try new NexoraModel2MainnetFactory(ADMIN, FUNDER, address(0), wallets) { revert("zero allocator accepted"); }
        catch {}
    }

    function testFactoryRejectsUnreachableRoleOrBeneficiary() public {
        address nextFactory = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        try new NexoraModel2MainnetFactory(nextFactory, FUNDER, ALLOCATOR, wallets) { revert("factory admin accepted"); }
        catch (bytes memory reason) { require(bytes4(reason) == NexoraModel2MainnetFactory.InaccessibleRole.selector, "wrong role revert"); }
        nextFactory = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        address nextSplitter = vm.computeCreateAddress(nextFactory, 1);
        try new NexoraModel2MainnetFactory(ADMIN, nextSplitter, ALLOCATOR, wallets) { revert("splitter funder accepted"); }
        catch (bytes memory reason) { require(bytes4(reason) == NexoraModel2MainnetFactory.InaccessibleRole.selector, "wrong funder revert"); }
        nextFactory = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        address[11] memory brokenWallets = wallets;
        brokenWallets[0] = nextFactory;
        try new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, brokenWallets) { revert("factory beneficiary accepted"); }
        catch (bytes memory reason) { require(bytes4(reason) == NexoraModel2MainnetFactory.InaccessibleBeneficiary.selector, "wrong beneficiary revert"); }
    }

    function testFundedDepositRewardAndSharedWithdrawalCapLocally() public {
        NexoraModel2MainnetFactory f = new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, wallets);
        NexoraModel2MainnetVault v = f.vault();
        NexoraRevenueSplitter s = f.splitter();
        token.mint(ALICE, 1000 * U);
        vm.prank(ALICE); token.approve(address(v), 1000 * U);
        vm.prank(ALICE); v.deposit(1000 * U, address(0));
        (uint256 gross, uint256 basis, uint256 principal, uint256 reward, uint256 cap) = v.accountSnapshot(ALICE);
        require(gross == 1000 * U && basis == 1000 * U && principal == 800 * U && reward == 0 && cap == 200 * U, "bad entry");
        require(s.claimable(wallets[0]) == 60 * U && s.claimable(wallets[1]) == 14 * U && s.totalClaimable() == 200 * U, "bad shares");
        token.mint(FUNDER, 10 * U);
        vm.prank(FUNDER); token.approve(address(v), 10 * U);
        vm.prank(FUNDER); v.fundRewards(10 * U);
        vm.warp(T + 1 days);
        vm.prank(ALLOCATOR); v.allocateReward(ALICE, 10 * U, bytes32(uint256(1)));
        require(v.isSolvent() && s.isSolvent(), "not fully backed");
        vm.warp(T + 90 days);
        vm.prank(ALICE); require(v.claimRewards() == 10 * U, "reward not paid");
        vm.prank(ALICE); v.withdrawPrincipal(190 * U);
        require(v.remainingWithdrawalCap(ALICE) == 0 && token.balanceOf(ALICE) == 200 * U, "shared cap broken");
        vm.warp(T + 91 days);
        require(v.remainingWithdrawalCap(ALICE) == 200 * U, "rolling window did not expire");
        require(v.isSolvent() && s.isSolvent(), "exit broke backing");
    }

    function testSameOwnerRolesArePossibleButDoNotProveControl() public {
        NexoraModel2MainnetFactory f = new NexoraModel2MainnetFactory(ADMIN, ADMIN, ADMIN, wallets);
        NexoraModel2MainnetVault v = f.vault();
        require(v.hasRole(v.DEFAULT_ADMIN_ROLE(), ADMIN) && v.hasRole(v.FUNDER_ROLE(), ADMIN) &&
            v.hasRole(v.ALLOCATOR_ROLE(), ADMIN), "selected roles did not persist");
    }

    function testMainnetCandidateThreeLevelFundedReferralsLocally() public {
        NexoraModel2MainnetFactory f = new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, wallets);
        NexoraModel2MainnetVault v = f.vault();
        address[4] memory members = [ALICE, address(0xA05), address(0xA06), address(0xA07)];
        for (uint256 i; i < members.length; ++i) {
            token.mint(members[i], 1000 * U);
            vm.prank(members[i]); token.approve(address(v), 1000 * U);
            vm.prank(members[i]); v.deposit(1000 * U, i == 0 ? address(0) : members[i - 1]);
        }
        require(v.teamVolume(members[0]) == 3000 * U && v.largestBranchVolume(members[0]) == 3000 * U,
            "three-level volume mismatch");
        token.mint(FUNDER, 125 * U / 10);
        vm.prank(FUNDER); token.approve(address(v), 125 * U / 10);
        vm.prank(FUNDER); v.fundRewards(125 * U / 10);
        vm.warp(T + 1 days);
        for (uint256 i = 1; i < members.length; ++i) v.syncDirect(members[i]);
        vm.prank(ALLOCATOR); v.allocateReward(members[3], 10 * U, bytes32(uint256(1)));
        require(v.getAccount(members[2]).referralRewards == 15 * U / 10, "level 1 mismatch");
        require(v.getAccount(members[1]).referralRewards == 7 * U / 10, "level 2 mismatch");
        require(v.getAccount(members[0]).referralRewards == 3 * U / 10, "level 3 mismatch");
        require(v.getAccount(members[3]).baseRewards == 10 * U && v.isSolvent(), "funded reward mismatch");
        vm.warp(T + 90 days);
        vm.prank(members[0]); require(v.claimRewards() == 3 * U / 10, "level 3 claim failed");
        vm.prank(members[1]); require(v.claimRewards() == 7 * U / 10, "level 2 claim failed");
        vm.prank(members[2]); require(v.claimRewards() == 15 * U / 10, "level 1 claim failed");
        vm.prank(members[3]); require(v.claimRewards() == 10 * U, "base claim failed");
        require(v.totalClaimableRewards() == 0 && v.isSolvent(), "claim ledger mismatch");
    }

    function testOneHundredAccountsCompleteLocalChain56Lifecycle() public {
        NexoraModel2MainnetFactory f = new NexoraModel2MainnetFactory(ADMIN, FUNDER, ALLOCATOR, wallets);
        NexoraModel2MainnetVault v = f.vault();
        NexoraRevenueSplitter s = f.splitter();
        for (uint256 i; i < 100; ++i) {
            address member = address(uint160(0x10000 + i));
            token.mint(member, 1000 * U);
            vm.prank(member); token.approve(address(v), 1000 * U);
            vm.prank(member); v.deposit(1000 * U, address(0));
        }
        token.mint(FUNDER, 1000 * U);
        vm.prank(FUNDER); token.approve(address(v), 1000 * U);
        vm.prank(FUNDER); v.fundRewards(1000 * U);
        vm.warp(T + 1 days);
        for (uint256 i; i < 100; ++i) {
            address member = address(uint160(0x10000 + i));
            vm.prank(ALLOCATOR); v.allocateReward(member, 10 * U, bytes32(i + 1));
            vm.prank(member); v.reinvestRewards(5 * U);
        }
        require(v.totalPrincipal() == 80_400 * U && v.totalClaimableRewards() == 500 * U, "wrong totals");
        require(s.totalClaimable() == 20_100 * U && v.isSolvent() && s.isSolvent(), "unbacked allocation");
        for (uint256 day; day < 5; ++day) {
            vm.warp(T + (90 + day) * 1 days);
            for (uint256 i; i < 100; ++i) {
                address member = address(uint160(0x10000 + i));
                vm.prank(member); v.withdrawPrincipal(day == 4 ? 4 * U : 200 * U);
                if (day == 4) { vm.prank(member); v.claimRewards(); }
            }
            require(v.isSolvent() && s.isSolvent(), "insolvency during exits");
        }
        require(v.totalPrincipal() == 0 && v.totalClaimableRewards() == 0, "residual user liabilities");
        for (uint256 i; i < 100; ++i) {
            address member = address(uint160(0x10000 + i));
            require(token.balanceOf(member) == 809 * U, "member proceeds mismatch");
        }
    }
}
