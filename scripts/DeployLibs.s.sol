// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "forge-std/Script.sol";

import {MockRegistry} from "../contracts/mock/MockRegistry.sol";

contract DeployLibs is Script {
    MockRegistry registry;

    constructor() {}

    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("deployer: ", deployer);
        vm.deal(deployer, type(uint64).max);
        vm.startBroadcast(deployerKey);
        registry = new MockRegistry();

        address creditLib = registry.creditLib();
        console.log("creditLib", creditLib);
        vm.stopBroadcast();
    }
}
