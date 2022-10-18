// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "chainlink/interfaces/FeedRegistryInterface.sol";
import {Denominations} from "chainlink/Denominations.sol";
import "../../interfaces/IOracle.sol";

contract Oracle is IOracle {
    FeedRegistryInterface internal registry;

    constructor(address _registry) {
        registry = FeedRegistryInterface(_registry);
    }

    /**
     * Returns the latest price in USD to 8 decimals
     */
    function getLatestAnswer(address token) external returns (int256) {
        (
            /* uint80 roundID */
            ,
            int256 price,
            /* uint80 startedAt */
            ,
            /* uint80 timeStamp */
            ,
            /* uint80 answeredInRound */
        ) = registry.latestRoundData(token, Denominations.USD);

        return price;
    }
}
