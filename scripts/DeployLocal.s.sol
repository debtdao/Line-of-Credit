// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./DeployBase.s.sol";
import {SimpleOracle} from "../contracts/mock/SimpleOracle.sol";

contract DeployLocal is DeployBase {
    SimpleOracle mockOracle; // would be feed registry on Goerli

    address arbiter = address(1);
    address swapTarget = address(2);
    address feedRegistry = address(3);

    address tokenA = address(4);
    address tokenB = address(5);

    constructor() {}

    function run() public {
        console.log("Starting local deployment");

        // uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // address deployer = vm.addr(deployerKey);

        // anvil private key
        uint256 deployerKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        console.log("deployer balance", deployer.balance);

        mockOracle = new SimpleOracle(tokenA, tokenB);

        run(arbiter, swapTarget, address(mockOracle));
    }
}
