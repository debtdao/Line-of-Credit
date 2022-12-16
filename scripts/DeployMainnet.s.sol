// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./DeployBase.s.sol";

import {Oracle} from "../contracts/modules/oracle/Oracle.sol";

contract DeployMainnet is DeployBase {
    Oracle oracle;

    address arbiter = address(0);
    address swapTarget = address(0);
    address feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf; // TODO: confirm this

    function run() public {
        console.log("Starting Mainnet deployment");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        oracle = new Oracle(feedRegistry);

        run(arbiter, swapTarget, address(oracle));
    }
}
