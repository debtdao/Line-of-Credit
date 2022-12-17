// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./DeployBase.s.sol";

import {Oracle} from "../contracts/modules/oracle/Oracle.sol";

contract DeployMainnet is DeployBase {
    Oracle oracle;

    address arbiter = 0xE9039a6968ED998139e023ed8D41c7fA77B7fF7A; // DD
    address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // 0x
    address feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf; // Chainlink

    function run() public {
        console.log("Starting Mainnet deployment");
        uint256 deployerKey = vm.envUint("DEPLOYER_MAINNET_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        oracle = new Oracle(feedRegistry);

        run(arbiter, swapTarget, address(oracle));
    }
}
