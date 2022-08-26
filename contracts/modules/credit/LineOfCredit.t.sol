pragma solidity ^0.8.9;


import "forge-std/Test.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LineLib} from "../../utils/LineLib.sol";
import {CreditLib} from "../../utils/CreditLib.sol";
import {CreditListLib} from "../../utils/CreditListLib.sol";
import {MutualConsent} from "../../utils/MutualConsent.sol";

import {LineOfCredit} from "./LineOfCredit.sol";

import {IOracle} from "../../interfaces/IOracle.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";

import { RevenueToken } from "../../mock/RevenueToken.sol";
import { SimpleOracle } from "../../mock/SimpleOracle.sol";

contract LineTest is Test{

    SimpleOracle oracle;
    address borrower;
    address arbiter;
    address lender;
    uint ttl = 150 days;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    LineOfCredit line;
    uint mintAmount = 100 ether;
    uint MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function setUp() public {
        borrower = address(10);
        arbiter = address(this);
        lender = address(20);

        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        RevenueToken unsupportedToken;

        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));

        line = new LineOfCredit(
            address(oracle),
            arbiter,
            borrower,
            ttl
        ); 
        assertEq(uint(line.init()), uint(LineLib.STATUS.ACTIVE));


    }

    function _mintAndApprove() internal {
        deal(lender, mintAmount);

        supportedToken1.mint(borrower, mintAmount);
        supportedToken1.mint(lender, mintAmount);
        supportedToken2.mint(borrower, mintAmount);
        supportedToken2.mint(lender, mintAmount);
        unsupportedToken.mint(borrower, mintAmount);
        unsupportedToken.mint(lender, mintAmount);

        vm.startPrank(borrower);
        supportedToken1.approve(address(escrow), MAX_INT);
        supportedToken1.approve(address(line), MAX_INT);
        supportedToken2.approve(address(escrow), MAX_INT);
        supportedToken2.approve(address(line), MAX_INT);
        unsupportedToken.approve(address(escrow), MAX_INT);
        unsupportedToken.approve(address(line), MAX_INT);
        vm.stopPrank();

        vm.startPrank(lender);
        supportedToken1.approve(address(escrow), MAX_INT);
        supportedToken1.approve(address(line), MAX_INT);
        supportedToken2.approve(address(escrow), MAX_INT);
        supportedToken2.approve(address(line), MAX_INT);
        unsupportedToken.approve(address(escrow), MAX_INT);
        unsupportedToken.approve(address(line), MAX_INT);
        vm.stopPrank();
>>>>>>> 841fe2e9d254dcde1db16816df117ae390d20c8e
    }


}
