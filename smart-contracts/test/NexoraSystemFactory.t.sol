// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraSystemFactory} from "../src/NexoraSystemFactory.sol";
import {NexoraProfitVault} from "../src/NexoraProfitVault.sol";
import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {NexoraRevenueRouter} from "../src/NexoraRevenueRouter.sol";
import {MockUSDT} from "./MockUSDT.sol";

interface VmMainnet {
    function chainId(uint256 newChainId) external;
    function prank(address sender) external;
    function warp(uint256 newTimestamp) external;
    function etch(address target, bytes calldata code) external;
}

contract NexoraSystemFactoryTest {
    VmMainnet private constant vm =
        VmMainnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant U = 1e18;
    address private constant ADMIN = address(0xABCD);
    address private constant ALLOCATOR = address(0xA220);
    address private constant USER = address(0xA11CE);

    MockUSDT private token;
    NexoraSystemFactory private factory;
    address[11] private recipients;

    function setUp() public {
        vm.chainId(97);
        vm.warp(1_000_000);
        token = new MockUSDT();
        recipients[0] = address(0xF00D);
        for (uint256 i = 1; i < recipients.length; ++i) {
            recipients[i] = address(uint160(0xF00D + i));
        }
        factory = new NexoraSystemFactory(
            address(token), ADMIN, address(this), ALLOCATOR, recipients
        );
        token.mint(address(this), 5_000 * U);
        token.mint(USER, 1_000 * U);
    }

    function _eq(uint256 actual, uint256 expected) private pure {
        require(actual == expected, "Unexpected amount");
    }

    function testFactoryWiresRolesWithoutResidualFactoryAccess() public view {
        NexoraProfitVault vault = factory.vault();
        NexoraRevenueSplitter splitter = factory.splitter();
        NexoraRevenueRouter router = factory.router();

        require(address(router.vault()) == address(vault), "Wrong vault");
        require(address(router.splitter()) == address(splitter), "Wrong splitter");
        require(vault.hasRole(vault.FUNDER_ROLE(), address(router)), "No router funder on vault");
        require(splitter.hasRole(splitter.FUNDER_ROLE(), address(router)), "No router funder on splitter");
        require(!vault.hasRole(vault.FUNDER_ROLE(), address(factory)), "Factory can fund vault");
        require(!splitter.hasRole(splitter.FUNDER_ROLE(), address(factory)), "Factory can fund splitter");
        require(!vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(factory)), "Factory still vault admin");
        require(!splitter.hasRole(splitter.DEFAULT_ADMIN_ROLE(), address(factory)), "Factory still splitter admin");
        require(!vault.hasRole(vault.GUARDIAN_ROLE(), address(factory)), "Factory remains guardian");
        require(!splitter.hasRole(splitter.GUARDIAN_ROLE(), address(factory)), "Factory remains guardian");
        require(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN), "Governance missing vault admin");
        require(splitter.hasRole(splitter.DEFAULT_ADMIN_ROLE(), ADMIN), "Governance missing splitter admin");
        require(vault.hasRole(vault.GUARDIAN_ROLE(), ADMIN), "Governance missing guardian");
        require(splitter.hasRole(splitter.GUARDIAN_ROLE(), ADMIN), "Governance missing guardian");
        require(router.hasRole(router.DEFAULT_ADMIN_ROLE(), ADMIN), "Governance missing router admin");
        require(router.hasRole(router.GUARDIAN_ROLE(), ADMIN), "Governance missing router guardian");
        require(router.hasRole(router.REVENUE_FUNDER_ROLE(), address(this)), "Funder missing");
        require(vault.hasRole(vault.ALLOCATOR_ROLE(), ALLOCATOR), "Allocator missing");
        _eq(splitter.shareWeights(0), 50);
        for (uint256 i = 1; i < 11; ++i) _eq(splitter.shareWeights(i), 7);
    }

    function testFactoryRevenueRoutingAndUserWithdrawal() public {
        NexoraProfitVault vault = factory.vault();
        NexoraRevenueSplitter splitter = factory.splitter();
        NexoraRevenueRouter router = factory.router();

        vm.prank(USER);
        token.approve(address(vault), type(uint256).max);
        vm.prank(USER);
        vault.deposit(100 * U, address(0));

        token.approve(address(router), 1_000 * U);
        router.fundAndRoute(1_000 * U, bytes32(uint256(1)));
        _eq(vault.totalPrincipal(), 100 * U);
        _eq(vault.unallocatedRewards(), 760 * U);
        _eq(splitter.totalClaimable(), 240 * U);
        _eq(splitter.claimable(recipients[0]), 100 * U);
        for (uint256 i = 1; i < 11; ++i) {
            _eq(splitter.claimable(recipients[i]), 14 * U);
        }
        uint256 balanceBefore = token.balanceOf(USER);
        vm.warp(block.timestamp + 90 days);
        for (uint256 i; i < 5; ++i) {
            vm.prank(USER);
            vault.withdrawPrincipal(20 * U);
            vm.warp(block.timestamp + 1 days);
        }
        _eq(token.balanceOf(USER), balanceBefore + 100 * U);
        _eq(vault.totalPrincipal(), 0);
        require(vault.isSolvent() && splitter.isSolvent(), "Not solvent");
    }

    function testOnlyIntendedFunderCanRoute() public {
        NexoraRevenueRouter router = factory.router();
        vm.prank(USER);
        (bool ok,) = address(router).call(
            abi.encodeCall(NexoraRevenueRouter.fundAndRoute, (100 * U, bytes32(uint256(10))))
        );
        require(!ok, "Unauthorized caller funded router");
    }

    function testRejectWrongNetwork() public {
        vm.chainId(1);
        bool rejected;
        try new NexoraSystemFactory(
            address(token), ADMIN, address(this), ALLOCATOR, recipients
        ) returns (NexoraSystemFactory) {} catch { rejected = true; }
        require(rejected, "Unexpected deployment on Ethereum mainnet");
    }

    function testMainnetRejectUnverifiedToken() public {
        vm.chainId(56);
        bool rejected;
        try new NexoraSystemFactory(
            address(token), ADMIN, address(this), ALLOCATOR, recipients
        ) returns (NexoraSystemFactory) {} catch { rejected = true; }
        require(rejected, "Wrong mainnet token was accepted");
    }

    function testMainnetRequiresDeployedContractForGovernance() public {
        vm.chainId(56);
        // Only simulate the official address on local EVM; NEVER deploy this mock.
        address pinned = factory.MAINNET_BINANCE_PEG_USDT();
        vm.etch(pinned, address(token).code);
        bool rejected;
        try new NexoraSystemFactory(
            pinned, ADMIN, address(this), ALLOCATOR, recipients
        ) returns (NexoraSystemFactory) {} catch { rejected = true; }
        require(rejected, "An EOA was accepted as BSC mainnet governance");
    }

    function testMainnetContractGovernanceBootstrapsWithoutDeployerAdmin() public {
        vm.chainId(56);
        address pinned = factory.MAINNET_BINANCE_PEG_USDT();
        // Test-only bytecode at the pinned address, not a real mainnet fork.
        vm.etch(pinned, address(token).code);
        DummyAdmin gov = new DummyAdmin();
        NexoraSystemFactory f = new NexoraSystemFactory(
            pinned, address(gov), address(this), ALLOCATOR, recipients
        );
        require(f.vault().hasRole(f.vault().DEFAULT_ADMIN_ROLE(), address(gov)),
            "Vault governance was not transferred");
        require(f.splitter().hasRole(f.splitter().DEFAULT_ADMIN_ROLE(), address(gov)),
            "Splitter governance was not transferred");
        require(f.router().hasRole(f.router().DEFAULT_ADMIN_ROLE(), address(gov)),
            "Router governance was not transferred");
        require(!f.vault().hasRole(f.vault().DEFAULT_ADMIN_ROLE(), address(f)),
            "Factory retains vault admin");
        require(!f.splitter().hasRole(f.splitter().DEFAULT_ADMIN_ROLE(), address(f)),
            "Factory retains splitter admin");
    }

    function testRoleSeparationIsMandatory() public {
        bool rejected;
        try new NexoraSystemFactory(
            address(token), ADMIN, ADMIN, ALLOCATOR, recipients
        ) returns (NexoraSystemFactory) {} catch { rejected = true; }
        require(rejected, "Admin and funder can be same key");
    }

    function testDuplicateRecipientIsRejected() public {
        recipients[10] = recipients[0];
        bool rejected;
        try new NexoraSystemFactory(
            address(token), ADMIN, address(this), ALLOCATOR, recipients
        ) returns (NexoraSystemFactory) {} catch { rejected = true; }
        require(rejected, "Duplicate payout wallet accepted");
    }

    function testZeroWalletIsRejected() public {
        recipients[5] = address(0);
        bool rejected;
        try new NexoraSystemFactory(
            address(token), ADMIN, address(this), ALLOCATOR, recipients
        ) returns (NexoraSystemFactory) {} catch { rejected = true; }
        require(rejected, "Zero beneficiary accepted");
    }
}

contract DummyAdmin { }
