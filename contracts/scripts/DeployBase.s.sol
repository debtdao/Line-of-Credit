// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "forge-std/Script.sol";

import {Oracle} from "../modules/oracle/Oracle.sol";
import {LineFactory} from "../modules/factories/LineFactory.sol";
import {ModuleFactory} from "../modules/factories/ModuleFactory.sol";

abstract contract DeployBase is Script {
    Oracle oracle;
    LineFactory lineFactory;
    ModuleFactory moduleFactory;

    // function run() public {
    //     console.log('running');
    // }

    function run(address arbiter_, address swapTarget_, address feedRegistry_) public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("deployer: ", deployer);

        vm.deal(deployer, type(uint64).max);
        console.log(deployer.balance);

        vm.startBroadcast(deployerKey);

        oracle = new Oracle(feedRegistry_);

        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(
            address(moduleFactory),
            arbiter_,
            address(oracle),
            swapTarget_
        );

        vm.stopBroadcast();

        // log the deployed contracts
        console.log("Oracle:", address(oracle));
        console.log("Module Factory:", address(moduleFactory));
        console.log("Line Factory:", address(lineFactory));
    }
}
