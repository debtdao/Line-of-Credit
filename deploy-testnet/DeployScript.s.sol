pragma solidity ^0.8.9;

import {Script} from "../lib/forge-std/src/Script.sol";
import {CreditLib} from "../contracts/utils/CreditLib.sol";
import {CreditListLib} from "../contracts/utils/CreditListLib.sol";
import {LineLib} from "../contracts/utils/LineLib.sol";
import {SpigotedLineLib} from "../contracts/utils/SpigotedLineLib.sol";
import {RevenueToken} from "../contracts/mock/RevenueToken.sol";
import {SimpleOracle} from "../contracts/mock/SimpleOracle.sol";
import {SecuredLine} from "../contracts/modules/credit/SecuredLine.sol";
import {Spigot} from "../contracts/modules/spigot/Spigot.sol";
import {Escrow} from "../contracts/modules/escrow/Escrow.sol";

import "hardhat/console.sol";

contract DeployScript is Script {
    Escrow escrow;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    SimpleOracle oracle;
    SecuredLine line;
    uint mintAmount = 100 ether;
    uint MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint minCollateralRatio = 1 ether; // 100%
    uint128 dRate = 100;
    uint128 fRate = 1;

    address borrower;
    address arbiter;
    address lender;

    function run() external {
        vm.startBroadcast();
        borrower = msg.sender;
        lender = msg.sender;
        arbiter = msg.sender;
        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();

        Spigot spigot = new Spigot(msg.sender, borrower, borrower);
        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));
        escrow = new Escrow(minCollateralRatio, address(oracle), msg.sender, borrower);

        line = new SecuredLine(
            address(oracle),
            arbiter,
            borrower,
            payable(address(0)),
            address(spigot),
            address(escrow),
            150 days,
            0
        );

        console.log("sender", msg.sender);
        console.log("spigot owner", spigot.owner());
        console.log("line address", address(line));

        escrow.updateLine(address(line));
        spigot.updateOwner(address(line));

        line.init();

        escrow.enableCollateral(address(supportedToken1));
        escrow.enableCollateral(address(supportedToken2));
        _mintAndApprove();
        escrow.addCollateral(1 ether, address(supportedToken2));

        vm.stopBroadcast();
    }

    function _mintAndApprove() internal {
        supportedToken1.mint(borrower, mintAmount);
        supportedToken1.approve(address(escrow), MAX_INT);
        supportedToken1.approve(address(line), MAX_INT);

        supportedToken2.mint(borrower, mintAmount);
        supportedToken2.approve(address(escrow), MAX_INT);
        supportedToken2.approve(address(line), MAX_INT);

        unsupportedToken.mint(borrower, mintAmount);
        unsupportedToken.approve(address(escrow), MAX_INT);
        unsupportedToken.approve(address(line), MAX_INT);
    }
}
