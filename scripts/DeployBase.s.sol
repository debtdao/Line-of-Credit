// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "forge-std/Script.sol";

import {Oracle} from "../contracts/modules/oracle/Oracle.sol";
import {LineFactory} from "../contracts/modules/factories/LineFactory.sol";
import {ModuleFactory} from "../contracts/modules/factories/ModuleFactory.sol";

abstract contract DeployBase is Script {
    LineFactory lineFactory;
    ModuleFactory moduleFactory;

    function run(address arbiter_, address swapTarget_, address oracle_) public {
        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(address(moduleFactory), arbiter_, oracle_, payable(swapTarget_));

        vm.stopBroadcast();

        // log the deployed contracts
        console.log("Oracle:", address(oracle_));
        console.log("Module Factory:", address(moduleFactory));
        console.log("Line Factory:", address(lineFactory));
    }
}
