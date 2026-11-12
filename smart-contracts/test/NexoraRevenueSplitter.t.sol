// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraRevenueSplitter} from "../src/NexoraRevenueSplitter.sol";
import {MockUSDT} from "./MockUSDT.sol";

interface VmRevenue {
    function prank(address) external;
}

contract NexoraRevenueSplitterTest {
    VmRevenue private constant vm = VmRevenue(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant U = 1e18;
    address private constant OUTSIDER = address(0xA11CE);

    MockUSDT private token;
    NexoraRevenueSplitter private splitter;
    address[11] private wallets;
    uint16[11] private weights;

    function setUp() public {
        token = new MockUSDT();
        // Splitter pool is 20% of amount, split 30% owner and 7% per company.
        // Gross revenue: 6% owner, 1.4% each company, 80% reserved in vault.
        wallets[0] = address(0x100);
        weights[0] = 30;
        for (uint256 i = 1; i < 11; ++i) {
            wallets[i] = address(uint160(0x100 + i));
            weights[i] = 7;
        }
        splitter = new NexoraRevenueSplitter(
            address(token), address(this), address(this), wallets
        );
        token.mint(address(this), 2_000_000 * U);
        token.approve(address(splitter), type(uint256).max);
    }

    function _assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "Unexpected amount");
    }

    function _expectFailure(bytes memory data) internal {
        (bool ok,) = address(splitter).call(data);
        require(!ok, "Expected failure");
    }

    function testOwnerAndTenWalletsArePaidInExactRatios() public {
        splitter.fundDistribution(100 * U, bytes32(uint256(1)));
        _assertEq(splitter.claimable(wallets[0]), 30 * U);
        for (uint256 i = 1; i < 11; ++i) {
            _assertEq(splitter.claimable(wallets[i]), 7 * U);
        }
        _assertEq(splitter.totalFunded(), 100 * U);
        _assertEq(splitter.totalClaimable(), 100 * U);
        require(splitter.isSolvent(), "Should be solvent");

        uint256 beforeOwnerBalance = token.balanceOf(wallets[0]);
        vm.prank(wallets[0]);
        splitter.claim();
        _assertEq(token.balanceOf(wallets[0]), beforeOwnerBalance + 30 * U);
        _assertEq(splitter.totalClaimed(), 30 * U);
        _assertEq(splitter.totalClaimable(), 70 * U);
        require(splitter.isSolvent(), "Should remain solvent");
    }

    function testRoundingDustGoesToOwnerNotToTheOperator() public {
        uint256 amount = 101; // just 101 wei, smallest token units
        splitter.fundDistribution(amount, bytes32(uint256(2)));
        _assertEq(splitter.claimable(wallets[0]), 31);
        for (uint256 i = 1; i < 11; ++i) {
            _assertEq(splitter.claimable(wallets[i]), 7);
        }
        _assertEq(splitter.totalClaimable(), amount);
    }

    function testDuplicateAndEmptyReportIdsCannotCreditTwice() public {
        splitter.fundDistribution(50 * U, bytes32(uint256(5)));
        _expectFailure(
            abi.encodeCall(NexoraRevenueSplitter.fundDistribution, (50 * U, bytes32(uint256(5))))
        );
        _expectFailure(
            abi.encodeCall(NexoraRevenueSplitter.fundDistribution, (50 * U, bytes32(0)))
        );
        _assertEq(splitter.totalFunded(), 50 * U);
    }

    function testOnlyFunderCanDistribute() public {
        vm.prank(OUTSIDER);
        _expectFailure(
            abi.encodeCall(NexoraRevenueSplitter.fundDistribution, (100 * U, bytes32(uint256(8))))
        );
        _assertEq(splitter.totalClaimable(), 0);
    }

    function testDirectTokenTransfersDoNotCreateShares() public {
        token.transfer(address(splitter), 70 * U);
        _assertEq(splitter.totalFunded(), 0);
        _assertEq(splitter.totalClaimable(), 0);
        _assertEq(splitter.claimable(wallets[0]), 0);
        require(splitter.isSolvent(), "No liabilities");
    }

    function testBeneficiariesMayClaimWhilePaused() public {
        splitter.fundDistribution(100 * U, bytes32(uint256(11)));
        splitter.pause();
        _expectFailure(
            abi.encodeCall(NexoraRevenueSplitter.fundDistribution, (50 * U, bytes32(uint256(12))))
        );
        vm.prank(wallets[1]);
        splitter.claim();
        _assertEq(token.balanceOf(wallets[1]), 7 * U);
    }

    function testDistributionPercentagesAreFixedAndNotCallerControlled() public view {
        _assertEq(splitter.OWNER_POOL_WEIGHT(), 30);
        _assertEq(splitter.COMPANY_POOL_WEIGHT(), 7);
        _assertEq(splitter.POOL_WEIGHT_DENOMINATOR(), 100);
        _assertEq(splitter.shareWeights(0), 30);
        uint256 weightsTotal = splitter.shareWeights(0);
        for (uint256 i = 1; i < 11; ++i) {
            _assertEq(splitter.shareWeights(i), 7);
            weightsTotal += splitter.shareWeights(i);
        }
        _assertEq(weightsTotal, 100);
    }

    function testDuplicateRecipientsAreRejected() public {
        address[11] memory invalid = wallets;
        invalid[10] = invalid[0];
        try new NexoraRevenueSplitter(
            address(token), address(this), address(this), invalid
        ) {
            revert("Duplicate recipients not rejected");
        } catch {}
    }

    function testPublicConfigurationIsImmutableAfterDeployment() public {
        (address[11] memory w, uint16[11] memory s) = splitter.getConfiguration();
        for (uint256 i; i < 11; ++i) {
            require(w[i] == wallets[i], "Wallet changed");
            _assertEq(s[i], weights[i]);
        }
        splitter.fundDistribution(9 * U, bytes32(uint256(23)));
        for (uint256 i; i < 11; ++i) {
            _assertEq(splitter.shareWeights(i), weights[i]);
            require(splitter.payoutWallets(i) == wallets[i], "Wallet changed after funding");
        }
    }

    function testFuzz_AllFundedUnitsRemainAccountedFor(uint96 raw) public {
        uint256 amount = 1 + uint256(raw) % (1_000_000 * U);
        splitter.fundDistribution(amount, bytes32(uint256(31415)));
        uint256 sum;
        for (uint256 i; i < 11; ++i) sum += splitter.claimable(wallets[i]);
        _assertEq(sum, amount);
        _assertEq(splitter.totalClaimable(), amount);
        require(splitter.isSolvent(), "Solvency invariant");
    }
}
