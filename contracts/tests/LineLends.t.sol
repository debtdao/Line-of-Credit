pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import {Denominations} from "chainlink/Denominations.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {LineLib} from "../utils/LineLib.sol";
import {CreditLib} from "../utils/CreditLib.sol";
import {CreditListLib} from "../utils/CreditListLib.sol";
import {MutualConsent} from "../utils/MutualConsent.sol";
import {LineOfCredit} from "../modules/credit/LineOfCredit.sol";

import {Escrow} from "../modules/escrow/Escrow.sol";
import {EscrowLib} from "../utils/EscrowLib.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {RevenueToken} from "../mock/RevenueToken.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";

contract LineLendsTest is Test {
    SimpleOracle oracle;
    address borrower;
    address arbiter;
    address lender;
    uint256 ttl = 150 days;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    LineOfCredit line;
    uint256 mintAmount = 100 ether;
    uint256 MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 minCollateralRatio = 1 ether; // 100%
    uint128 dRate = 100;
    uint128 fRate = 1;

    function setUp() public {
        borrower = address(10);
        arbiter = address(this);
        lender = address(20);

        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();

        oracle = new SimpleOracle(
            address(supportedToken1),
            address(supportedToken2)
        );

        line = new LineOfCredit(address(oracle), arbiter, borrower, ttl);
        assertEq(uint256(line.init()), uint256(LineLib.STATUS.ACTIVE));
        _mintAndApprove();
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
        supportedToken1.approve(address(line), MAX_INT);
        supportedToken2.approve(address(line), MAX_INT);
        unsupportedToken.approve(address(line), MAX_INT);
        vm.stopPrank();

        vm.startPrank(lender);
        supportedToken1.approve(address(line), MAX_INT);
        supportedToken2.approve(address(line), MAX_INT);
        unsupportedToken.approve(address(line), MAX_INT);
        vm.stopPrank();
    }

    function _addCredit(address token, uint256 amount) public {
        vm.startPrank(borrower);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
        vm.startPrank(lender);

        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
    }

    function test_interest_accrued_vs_interest_viewed_debt_not_updated() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);

        vm.warp(30 days);

        (,,uint256 interestAccrued,,,,,) = line.credits(id);

        assertEq(interestAccrued, 0);

        uint256 getInterest = line.interestAccrued(id);

        assertGt(getInterest, 0);

    }

    function test_interest_accrued_vs_interest_viewed_with_time() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);

        vm.warp(30 days);

        line.accrueInterest();
        (,,uint256 interestAccrued,,,,,) = line.credits(id);

        assertGt(interestAccrued, 0);

        uint256 getInterest = line.interestAccrued(id);

        assertEq(getInterest, interestAccrued);

    }


    function test_interest_accrued_equals_interest_viewed_with_no_time() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);

        line.accrueInterest();
        (,,uint256 interestAccrued,,,,,) = line.credits(id);

        uint256 getInterest = line.interestAccrued(id);

        assertEq(interestAccrued, 0);
        assertEq(getInterest, 0);
    }

}