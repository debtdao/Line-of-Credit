// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "forge-std/Script.sol";

import {SimpleOracle} from "../mock/SimpleOracle.sol";

contract DeployBase is Script {
    SimpleOracle oracle;

    constructor() {}

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("deployer: ", deployer);

        vm.deal(deployer, type(uint64).max);
        console.log(deployer.balance);

        vm.startBroadcast(deployerKey);
        oracle = new SimpleOracle(address(0), address(1));
    }
}
