// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./DeployBase.s.sol";
import {SimpleOracle} from "../contracts/mock/SimpleOracle.sol";

import {RevenueToken} from "../contracts/mock/RevenueToken.sol";

import {SimpleOracle} from "../contracts/mock/SimpleOracle.sol";

contract DeployLocal is DeployBase {
    SimpleOracle mockOracle; // would be feed registry on Goerli

    address arbiter = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720; // anvil [9]
    address swapTarget;
    address feedRegistry;

    RevenueToken tokenA;
    RevenueToken tokenB;

    SimpleOracle oracle;

    constructor() {}

    function run() public {
        console.log("Starting local deployment");

        // TODO: replace dynamically
        uint256 deployerKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; // anvil [1]
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        tokenA = new RevenueToken();
        tokenB = new RevenueToken();
        oracle = new SimpleOracle(address(tokenA), address(tokenB));
        // swapTarget = makeAddr("swapTarget");

        console.log("deployer balance", deployer.balance);
        console.log("tokenA", address(tokenA));
        console.log("tokenB", address(tokenB));
        console.log("oracle", address(oracle));
        // console.log("swapTarget", swapTarget);

        // run(arbiter, swapTarget, address(oracle));
    }
}
