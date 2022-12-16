// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./DeployBase.s.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";

contract DeployGoerli is DeployBase {
    SimpleOracle mockOracle; // would be feed registry on Goerli

    address arbiter = address(1);
    address swapTarget = address(2);
    address feedRegistry = address(3);

    address seeroCoin = address(4);
    address tokenB = address(5);

    constructor() {
        mockOracle = new SimpleOracle(seeroCoin, tokenB);
    }

    function run() public {
        console.log("Starting Goerli deployment");
        run(arbiter, swapTarget, feedRegistry);
    }
}
