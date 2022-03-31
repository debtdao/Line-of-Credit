// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "../interfaces/IOracle.sol";

contract Oracle is IOracle {
    FeedRegistryInterface internal registry;
    address public USD = 0x0000000000000000000000000000000000000348;

    constructor(address _registry) {
        registry = FeedRegistryInterface(_registry);
    }

    /**
     * Returns the latest price
     */
    function getLatestAnswer(address token) public view returns (int) {
        (
            /* uint80 roundID */, 
            int price,
            /* uint80 startedAt */,
            /* uint80 timeStamp */,
            /* uint80 answeredInRound */
        ) = registry.latestRoundData(token, USD); // all prices are in USD so we hardcode the address
        return price;
    }
}
