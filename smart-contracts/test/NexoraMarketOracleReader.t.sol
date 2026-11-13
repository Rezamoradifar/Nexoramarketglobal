// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraMarketOracleReader, INexoraMarketFeed}
    from "../src/NexoraMarketOracleReader.sol";

interface VmMarketRead {
    function prank(address) external;
    function warp(uint256) external;
}

contract MockNexoraMarketFeed is INexoraMarketFeed {
    uint8 private _decimals;
    uint80 public roundId;
    uint80 public answeredInRound;
    int256 public answer;
    uint256 public updatedAt;

    constructor() { _decimals = 8; }

    function setDecimals(uint8 d) external { _decimals = d; }
    function setRound(
        uint80 id, int256 value, uint256 updated, uint80 answered
    ) external {
        roundId = id;
        answer = value;
        updatedAt = updated;
        answeredInRound = answered;
    }
    function decimals() external view returns (uint8) { return _decimals; }
    function latestRoundData()
        external view returns (
            uint80, int256, uint256, uint256, uint80
        )
    {
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}

contract NexoraMarketOracleReaderTest {
    VmMarketRead private constant vm =
        VmMarketRead(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant BTC_USD = keccak256("BTC/USD");
    address private constant OUTSIDER = address(0xBAAD);

    NexoraMarketOracleReader private reader;
    MockNexoraMarketFeed private feed;

    function setUp() public {
        vm.warp(1_700_000_000);
        reader = new NexoraMarketOracleReader(address(this));
        feed = new MockNexoraMarketFeed();
        feed.setRound(3, 40_000 * 1e8, block.timestamp, 3);
    }

    function _expectLatestPriceReject() private view {
        (bool ok,) = address(reader).staticcall(
            abi.encodeCall(NexoraMarketOracleReader.latestPrice, (BTC_USD))
        );
        require(!ok, "Oracle accepted invalid or missing price");
    }

    function testOnlyConfiguredFreshPriceIsReadable() public {
        _expectLatestPriceReject();
        reader.configureFeed(BTC_USD, address(feed), 1 hours);
        (int256 p, uint8 d, uint256 updated, address proxy) = reader.latestPrice(BTC_USD);
        require(p == int256(40_000 * 1e8), "Wrong price");
        require(d == 8, "Wrong decimals");
        require(updated == block.timestamp, "Wrong update time");
        require(proxy == address(feed), "Wrong trusted feed proxy");
    }

    function testUnprivilegedAccountCannotChangeOrDisableMarket() public {
        vm.prank(OUTSIDER);
        (bool ok,) = address(reader).call(abi.encodeCall(
            NexoraMarketOracleReader.configureFeed, (BTC_USD, address(feed), uint48(1 hours))
        ));
        require(!ok, "Unprivileged feed registration accepted");
        reader.configureFeed(BTC_USD, address(feed), 1 hours);
        vm.prank(OUTSIDER);
        (ok,) = address(reader).call(abi.encodeCall(
            NexoraMarketOracleReader.disableFeed, (BTC_USD)
        ));
        require(!ok, "Unprivileged feed disabling accepted");
        (int256 p,,,) = reader.latestPrice(BTC_USD);
        require(p > 0, "Feed unexpectedly disabled");
    }

    function testRejectInvalidFeedAddressAndInvalidHeartbeat() public {
        (bool ok,) = address(reader).call(abi.encodeCall(
            NexoraMarketOracleReader.configureFeed, (bytes32(0), address(feed), uint48(1 hours))
        ));
        require(!ok, "Zero market identifier accepted");
        (ok,) = address(reader).call(abi.encodeCall(
            NexoraMarketOracleReader.configureFeed, (BTC_USD, address(0x1234), uint48(1 hours))
        ));
        require(!ok, "EOA/no-bytecode feed accepted");
        (ok,) = address(reader).call(abi.encodeCall(
            NexoraMarketOracleReader.configureFeed, (BTC_USD, address(feed), uint48(4 minutes))
        ));
        require(!ok, "Heartbeat below lower bound accepted");
        (ok,) = address(reader).call(abi.encodeCall(
            NexoraMarketOracleReader.configureFeed, (BTC_USD, address(feed), uint48(25 hours))
        ));
        require(!ok, "Heartbeat beyond upper bound accepted");

        feed.setDecimals(37);
        (ok,) = address(reader).call(abi.encodeCall(
            NexoraMarketOracleReader.configureFeed, (BTC_USD, address(feed), uint48(1 hours))
        ));
        require(!ok, "Oracle with implausible decimals accepted");
    }

    function testRejectStaleFutureEmptyNegativeAndUnansweredRounds() public {
        reader.configureFeed(BTC_USD, address(feed), 1 hours);
        feed.setRound(3, 40_000 * 1e8, block.timestamp - 1 hours - 1, 3);
        _expectLatestPriceReject();

        feed.setRound(3, 40_000 * 1e8, block.timestamp + 1, 3);
        _expectLatestPriceReject();

        feed.setRound(0, 40_000 * 1e8, block.timestamp, 0);
        _expectLatestPriceReject();

        feed.setRound(4, 0, block.timestamp, 4);
        _expectLatestPriceReject();

        feed.setRound(5, -1, block.timestamp, 5);
        _expectLatestPriceReject();

        feed.setRound(6, 40_000 * 1e8, 0, 6);
        _expectLatestPriceReject();

        feed.setRound(7, 40_000 * 1e8, block.timestamp, 6);
        _expectLatestPriceReject();

        feed.setRound(8, 40_000 * 1e8, block.timestamp, 8);
        (int256 p,,,) = reader.latestPrice(BTC_USD);
        require(p == int256(40_000 * 1e8), "Good round rejected after bad rounds");
    }

    function testAdminCanDisableConfiguredFeedAndConsumersCannotReadIt() public {
        reader.configureFeed(BTC_USD, address(feed), 1 hours);
        reader.disableFeed(BTC_USD);
        _expectLatestPriceReject();
        (bool ok,) = address(reader).call(abi.encodeCall(
            NexoraMarketOracleReader.disableFeed, (BTC_USD)
        ));
        require(!ok, "Double-disable succeeded");
        reader.configureFeed(BTC_USD, address(feed), 1 hours);
        (int256 p,,,) = reader.latestPrice(BTC_USD);
        require(p > 0, "Feed cannot be reconfigured after disable");
    }

    function testFuzz_FreshnessBoundaryEnforced(uint32 ageInSeconds) public {
        reader.configureFeed(BTC_USD, address(feed), 1 hours);
        uint256 age = uint256(ageInSeconds) % 7_201;
        feed.setRound(11, 52_000 * 1e8, block.timestamp - age, 11);
        if (age <= 1 hours) {
            (int256 p,,,) = reader.latestPrice(BTC_USD);
            require(p > 0, "Fresh feed unexpectedly failed");
        } else {
            _expectLatestPriceReject();
        }
    }
}
