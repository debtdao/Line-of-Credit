pragma solidity ^0.8.9;


import "forge-std/Test.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LineLib} from "../../utils/LineLib.sol";
import {CreditLib} from "../../utils/CreditLib.sol";
import {CreditListLib} from "../../utils/CreditListLib.sol";
import {MutualConsent} from "../../utils/MutualConsent.sol";
import {InterestRateCredit} from "../interest-rate/InterestRateCredit.sol";
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

}
