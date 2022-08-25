pragma solidity ^0.8.9;

import {Script} from "../lib/forge-std/src/Script.sol";
import {CreditLib } from "../contracts/utils/CreditLib.sol";
import {CreditListLib } from "../contracts/utils/CreditListLib.sol";
import {LineLib } from "../contracts/utils/LineLib.sol";
import {SpigotedLineLib } from "../contracts/utils/SpigotedLineLib.sol";
import {RevenueToken} from "../contracts/mock/RevenueToken.sol";
import {SimpleOracle} from "../contracts/mock/SimpleOracle.sol";
import {SecuredLine} from "../contracts/modules/credit/SecuredLine.sol";
import {Spigot} from  "../contracts/modules/spigot/Spigot.sol";
import {Escrow} from "../contracts/modules/escrow/Escrow.sol";

import "hardhat/console.sol";

contract DeployMainnetScript is Script {
    Escrow escrow;
    Spigot spigot;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    SimpleOracle oracle;
    SecuredLine line;
    
    uint mintAmount = 100 ether;
    uint MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint minCollateralRatio = 1 ether; // 100%
    uint128 drawnRate = 100;
    uint128 facilityRate = 1;

    address borrower;
    address arbiter;
    address lender;

    function run() external {
        vm.startBroadcast();
        
        vm.stopBroadcast();
    }
}