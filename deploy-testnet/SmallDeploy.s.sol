pragma solidity ^0.8.9;

import {Script} from "../lib/forge-std/src/Script.sol";
import {RevenueToken} from "../contracts/mock/RevenueToken.sol";

contract SmallDeploy is Script {
    RevenueToken token;
    function run() external{
        vm.startBroadcast();

        token = new RevenueToken();

        vm.stopBroadcast();
    }
}