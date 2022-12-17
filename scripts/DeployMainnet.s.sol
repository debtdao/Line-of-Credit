// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./DeployBase.s.sol";

import {Oracle} from "../contracts/modules/oracle/Oracle.sol";

contract DeployMainnet is DeployBase {
    Oracle oracle;

    address arbiter = 0xB2EB96f809A27bbA9E28a7faf8F4316414cec468; // DD
    address swapTarget = 0xdef1c0ded9bec7f1a1670819833240f027b25eff; // 0x
    address feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf; // Chainlink

    function run() public {
        console.log("Starting Mainnet deployment");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        oracle = new Oracle(feedRegistry);

        run(arbiter, swapTarget, address(oracle));
    }
}
