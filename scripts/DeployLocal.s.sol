// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./DeployBase.s.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";

contract DeployLocal is DeployBase {
    SimpleOracle mockOracle; // would be feed registry on Goerli

    address arbiter = address(1);
    address swapTarget = address(2);
    address feedRegistry = address(3);

    address tokenA = address(4);
    address tokenB = address(5);

    constructor() {
        mockOracle = new SimpleOracle(tokenA, tokenB);
    }

    function run() public {
        console.log("Starting local deployment");
        run(arbiter, swapTarget, address(mockOracle));
    }
}
