// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {MockAggregator} from "./MockAggregator.sol";

contract MockRegistry {
    mapping(address => int256) tokenPrices;

    mapping(address => MockAggregator) mockAggregators;

    constructor() {}

    function latestRoundData(
        address base,
        address quote
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return mockAggregators[base].getLatestRound();
    }

    function addToken(address token, int256 price) external {
        mockAggregators[token] = new MockAggregator(token, price);
    }

    function decimals(address base, address quote) external view returns (uint8) {
        return mockAggregators[base].decimals();
    }

    function overrideTokenTimestamp(address token, bool shouldOverride) external {
        mockAggregators[token].setOverrideTimestamp(shouldOverride);
    }

    function updateTokenPrice(address token, int256 price) external {
        mockAggregators[token].changePrice(price);
    }

    function updateTokenDecimals(address token, uint8 decimals_) external {
        mockAggregators[token].changeDecimals(decimals_);
    }

    function getAggregator(address token) external view returns (MockAggregator) {
        return mockAggregators[token];
    }
}
