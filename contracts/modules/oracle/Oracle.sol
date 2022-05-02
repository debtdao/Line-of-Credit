// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "../../interfaces/IOracle.sol";

contract Oracle is IOracle {
    FeedRegistryInterface internal registry;
    address public USD = 0x0000000000000000000000000000000000000348;

    constructor(address _registry) {
        registry = FeedRegistryInterface(_registry);
    }

    /**
     * Returns the latest price in USD
     */
    function getLatestAnswer(address token) external view returns (int) {
        (
            /* uint80 roundID */, 
            int price,
            /* uint80 startedAt */,
            /* uint80 timeStamp */,
            /* uint80 answeredInRound */
        ) = registry.latestRoundData(token, USD); // all prices are in USD so we hardcode the address

        uint8 decimals = registry.decimals(token, USD);
        
        return (price / int(10 ** decimals)); // scale down
    }
}
