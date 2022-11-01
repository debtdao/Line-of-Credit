// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "chainlink/interfaces/FeedRegistryInterface.sol";
import { Denominations } from "chainlink/Denominations.sol";
import "../../interfaces/IOracle.sol";

/**
 * @title   - Chainlink Feed Registry Wrapper
 * @notice  - simple contract that wraps Chainlink's Feed Registry to get asset prices for any tokens without needing to know the specific oracle address
 *          - only makes request for USD prices and returns results in standard 8 decimals for Chainlink USD feeds
 */
contract Oracle is IOracle {
    FeedRegistryInterface internal registry; 
    constructor(address _registry) {
        registry = FeedRegistryInterface(_registry);
    }

    /**
     * @return price - the latest price in USD to 8 decimals
     */
    function getLatestAnswer(address token) external returns (int) {
        (
            /* uint80 roundID */, 
            int price,
            /* uint80 startedAt */,
            /* uint80 timeStamp */,
            /* uint80 answeredInRound */
        ) = registry.latestRoundData(token, Denominations.USD);
        
        return price;
    }

    
}
