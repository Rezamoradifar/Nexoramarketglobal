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
    uint16[11] private bps;

    function setUp() public {
        token = new MockUSDT();
        // TEST FIXTURES ONLY: 20% owner and 8% each for ten other addresses.
        // PRODUCTION shares must be agreed before deploying a fresh contract.
        wallets[0] = address(0x100);
        bps[0] = 2_000;
        for (uint256 i = 1; i < 11; ++i) {
            wallets[i] = address(uint160(0x100 + i));
            bps[i] = 800;
        }
        splitter = new NexoraRevenueSplitter(
            address(token), address(this), address(this), wallets, bps
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
        _assertEq(splitter.claimable(wallets[0]), 20 * U);
        for (uint256 i = 1; i < 11; ++i) {
            _assertEq(splitter.claimable(wallets[i]), 8 * U);
        }
        _assertEq(splitter.totalFunded(), 100 * U);
        _assertEq(splitter.totalClaimable(), 100 * U);
        require(splitter.isSolvent(), "Should be solvent");

        uint256 beforeOwnerBalance = token.balanceOf(wallets[0]);
        vm.prank(wallets[0]);
        splitter.claim();
        _assertEq(token.balanceOf(wallets[0]), beforeOwnerBalance + 20 * U);
        _assertEq(splitter.totalClaimed(), 20 * U);
        _assertEq(splitter.totalClaimable(), 80 * U);
        require(splitter.isSolvent(), "Should remain solvent");
    }

    function testRoundingDustGoesToOwnerNotToTheOperator() public {
        uint256 amount = 101; // just 101 wei, smallest token units
        splitter.fundDistribution(amount, bytes32(uint256(2)));
        _assertEq(splitter.claimable(wallets[0]), 21);
        for (uint256 i = 1; i < 11; ++i) {
            _assertEq(splitter.claimable(wallets[i]), 8);
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
        _assertEq(token.balanceOf(wallets[1]), 8 * U);
    }

    function testInvalidSharesAreRejected() public {
        uint16[11] memory wrong = bps;
        wrong[1] = 801;
        try new NexoraRevenueSplitter(
            address(token), address(this), address(this), wallets, wrong
        ) {
            revert("Shares not rejected");
        } catch {}

        wrong = bps;
        wrong[1] = 0;
        try new NexoraRevenueSplitter(
            address(token), address(this), address(this), wallets, wrong
        ) {
            revert("Zero share not rejected");
        } catch {}
    }

    function testDuplicateRecipientsAreRejected() public {
        address[11] memory invalid = wallets;
        invalid[10] = invalid[0];
        try new NexoraRevenueSplitter(
            address(token), address(this), address(this), invalid, bps
        ) {
            revert("Duplicate recipients not rejected");
        } catch {}
    }

    function testPublicConfigurationIsImmutableAfterDeployment() public {
        (address[11] memory w, uint16[11] memory s) = splitter.getConfiguration();
        for (uint256 i; i < 11; ++i) {
            require(w[i] == wallets[i], "Wallet changed");
            _assertEq(s[i], bps[i]);
        }
        splitter.fundDistribution(9 * U, bytes32(uint256(23)));
        for (uint256 i; i < 11; ++i) {
            _assertEq(splitter.sharesBps(i), bps[i]);
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
