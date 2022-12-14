pragma solidity 0.8.9;

import "forge-std/Test.sol";

import { Denominations } from "chainlink/Denominations.sol";

import { IEscrow } from "../contracts/interfaces/IEscrow.sol";
import { LineLib } from "../contracts/utils/LineLib.sol";
import { IEscrowedLine } from "../contracts/interfaces/IEscrowedLine.sol";
import { ILineOfCredit } from "../contracts/interfaces/ILineOfCredit.sol";
import { SimpleOracle } from "../contracts/mock/SimpleOracle.sol";
import { RevenueToken } from "../contracts/mock/RevenueToken.sol";
import { Escrow } from "../contracts/modules/escrow/Escrow.sol";
import { MockEscrowedLine } from '../contracts/mock/MockEscrowedLine.sol';
import { ZeroEx } from "../contracts/mock/ZeroEx.sol";
import { MockLine } from "../contracts/mock/MockLine.sol";


contract EscrowedLineTest is Test {

    
    MockEscrowedLine line;
    Escrow escrow;
    
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;

    // Named vars for common inputs
    address constant revenueContract = address(0xdebf);
    uint lentAmount = 1 ether;
    
    uint128 constant dRate = 100;
    uint128 constant fRate = 1;
    uint constant ttl = 10 days; // allows us t
    uint8 constant ownerSplit = 10; // 10% of all borrower revenue goes to spigot

    uint constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint constant MAX_REVENUE = MAX_INT / 100;
    uint32 minCollateralRatio = 10000; // 100%
    uint mintAmount = 100 ether;

    // Line access control vars
    address private arbiter = address(this);
    address private borrower = address(10);
    address private lender = address(20);

    address private testaddr = makeAddr("test");
    SimpleOracle private oracle;

    function setUp() public {
        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();

        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));
        escrow = new Escrow(minCollateralRatio, address(oracle), arbiter, borrower);
        line = new MockEscrowedLine(
            address(escrow),
            address(oracle),
            arbiter,
            borrower,
            ttl
        );

        escrow.updateLine(address(line));
        assertEq(uint(line.init()), uint(LineLib.STATUS.ACTIVE));

        _mintAndApprove();
        escrow.enableCollateral( address(supportedToken1));
        escrow.enableCollateral( address(supportedToken2));

        vm.startPrank(borrower);
        escrow.addCollateral(1 ether, address(supportedToken2));
        vm.stopPrank();
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

    }

    function _addCredit(address token, uint256 amount) public {
        hoax(borrower);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
        hoax(lender);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
    }

    

   function test_cannot_liquidate_escrow_if_cratio_above_min() public {
        hoax(borrower);
        line.addCredit(dRate, fRate, 1 ether, address(supportedToken1), lender);
        hoax(lender);
        bytes32 id = line.addCredit(dRate, fRate, 1 ether, address(supportedToken1), lender);
        hoax(borrower);
        line.borrow(id, 1 ether);

        vm.expectRevert(ILineOfCredit.NotLiquidatable.selector); 
        line.liquidate(1 ether, address(supportedToken2));
    }

    function test_can_liquidate_escrow_if_cratio_below_min() public {
        _addCredit(address(supportedToken1), 1 ether);
        uint balanceOfEscrow = supportedToken2.balanceOf(address(escrow));
        uint balanceOfArbiter = supportedToken2.balanceOf(arbiter);
        
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        (uint p,) = line.updateOutstandingDebt();
        assertGt(p, 0);
        console.log('checkpoint');
        oracle.changePrice(address(supportedToken2), 1);
        line.liquidate(1 ether, address(supportedToken2));
        assertEq(
        balanceOfEscrow, supportedToken1.balanceOf(address(escrow)) + 1 ether, "Escrow balance should have increased by 1e18");
        assertEq(balanceOfArbiter, supportedToken2.balanceOf(arbiter) - 1 ether, "Arbiter balance should have decreased by 1e18");
    }

    function test_line_is_uninitilized_if_escrow_not_owned() public {
        address mock = address(new MockLine(0, address(3)));
        
        Escrow e = new Escrow(minCollateralRatio, address(oracle), mock, borrower);
        MockEscrowedLine l = new MockEscrowedLine(
       
            address(escrow),
            address(oracle),
            arbiter,
            borrower,
            ttl
        );

        // configure other modules
       
        
        assertEq(uint(l.init()), uint(LineLib.STATUS.UNINITIALIZED));
    }

    function test_can_liquidate_anytime_if_escrow_cratio_below_min() public {
        _addCredit(address(supportedToken1), 1 ether);
        uint balanceOfEscrow = supportedToken2.balanceOf(address(escrow));
        uint balanceOfArbiter = supportedToken2.balanceOf(arbiter);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        (uint p, uint i) = line.updateOutstandingDebt();
        assertGt(p, 0);
        oracle.changePrice(address(supportedToken2), 1);
        line.liquidate(1 ether, address(supportedToken2));
        assertEq(balanceOfEscrow, supportedToken1.balanceOf(address(escrow)) + 1 ether, "Escrow balance should have increased by 1e18");
        assertEq(balanceOfArbiter, supportedToken2.balanceOf(arbiter) - 1 ether, "Arbiter balance should have decreased by 1e18");
    }
    
    function test_cannot_be_liquidatable_if_debt_is_0() public {

        assertEq(uint256(line.healthcheck()), uint256(LineLib.STATUS.ACTIVE));
    }
}
