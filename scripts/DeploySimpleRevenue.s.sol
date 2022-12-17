// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "forge-std/Script.sol";

import {SimpleRevenueContract} from "../contracts/mock/SimpleRevenueContract.sol";

contract DeploySimpleRevenueContract is Script {
    SimpleRevenueContract revenue;

    constructor() {}

    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("deployer: ", deployer);

        vm.startBroadcast(deployerKey);

        revenue = new SimpleRevenueContract(
            address(0x0980510F95F4fAB5629a497F9FeA58a1f44FC121),
            address(0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6)
        );

        vm.stopBroadcast();
    }
}
