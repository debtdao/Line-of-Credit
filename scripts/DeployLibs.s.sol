// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "forge-std/Script.sol";

import {LibRegistry} from "../contracts/utils/LibRegistry.sol";

contract DeployLibs is Script {
    LibRegistry registry;

    constructor() {}

    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_MAINNET_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("deployer: ", deployer);

        vm.startBroadcast(deployerKey);

        registry = new LibRegistry();

        vm.stopBroadcast();
    }
}
