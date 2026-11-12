// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraMarketOracleReader
 * @notice READ-ONLY interface for independently verified on-chain market feeds.
 * @dev This module can CONNECT to vetted EVM price-feed proxies (e.g. Chainlink
 * AggregatorV3Interface), but it NEVER custodies/approves/transfers tokens,
 * trades, lends, invests, updates vault principal or calculates investor yield.
 *
 * Admin must vet feed address, decimals, availability, license, update heartbeat,
 * and governance before activation. Operators cannot invent market prices here.
 * Not audited; this is only a market-connectivity integration prototype.
 */
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface INexoraMarketFeed {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external view returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract NexoraMarketOracleReader is AccessControl {
    struct FeedConfig {
        address proxy;
        uint48 maxAge;
        bool active;
    }
    mapping(bytes32 => FeedConfig) public feeds;

    event FeedConfigured(bytes32 indexed marketId, address indexed feedProxy, uint48 maxAge);
    event FeedDisabled(bytes32 indexed marketId);

    error InvalidAdmin();
    error InvalidMarket();
    error InvalidProxy();
    error InvalidMaxAge();
    error FeedNotActive();
    error StaleOrInvalidPrice();

    constructor(address admin_) {
        if (admin_ == address(0)) revert InvalidAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /**
     * E.g. marketId = keccak256("BTC/USD"). No contract address is
     * assumed or silently chosen; only independently verified proxies.
     */
    function configureFeed(bytes32 marketId, address proxy, uint48 maxAge)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (marketId == bytes32(0)) revert InvalidMarket();
        if (proxy.code.length == 0) revert InvalidProxy();
        if (maxAge < 5 minutes || maxAge > 24 hours) revert InvalidMaxAge();
        // Check that this contract exposes the expected aggregator interface.
        // It may still lie; use only reputable reviewed feeds, never use for custody.
        uint8 d = INexoraMarketFeed(proxy).decimals();
        if (d > 36) revert InvalidProxy();

        feeds[marketId] = FeedConfig(proxy, maxAge, true);
        emit FeedConfigured(marketId, proxy, maxAge);
    }

    function disableFeed(bytes32 marketId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!feeds[marketId].active) revert FeedNotActive();
        feeds[marketId].active = false;
        emit FeedDisabled(marketId);
    }

    function latestPrice(bytes32 marketId)
        external view returns (int256 answer, uint8 decimals, uint256 updatedAt, address proxy)
    {
        FeedConfig memory f = feeds[marketId];
        if (!f.active) revert FeedNotActive();
        (uint80 roundId, int256 value, , uint256 updated, ) =
            INexoraMarketFeed(f.proxy).latestRoundData();
        if (roundId == 0 || value <= 0 || updated == 0 ||
            updated > block.timestamp || block.timestamp - updated > f.maxAge) {
            revert StaleOrInvalidPrice();
        }
        return (value, INexoraMarketFeed(f.proxy).decimals(), updated, f.proxy);
    }
}
