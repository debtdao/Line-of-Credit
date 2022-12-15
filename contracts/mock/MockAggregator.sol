// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract MockAggregator {
    address public immutable token;

    bool overrideTimestamp;
    uint8 public decimals = 8;
    int256 price;

    constructor(address token_, int256 price_) {
        token = token_;
        price = price_;
    }

    function getLatestRound() external view returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80) {
        answer = price;
        updatedAt = overrideTimestamp ? block.timestamp : block.timestamp - 28 hours;
        return (0, answer, 0, updatedAt, 0);
    }

    function changePrice(int256 price_) external {
        price = price_;
    }

    function changeDecimals(uint8 newDecimals) external {
        decimals = newDecimals;
    }

    function setOverrideTimestamp(bool value) external {
        overrideTimestamp = value;
    }
}