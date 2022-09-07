pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LineLib} from "../utils/LineLib.sol";
import {CreditLib} from "../utils/CreditLib.sol";
import {CreditListLib} from "../utils/CreditListLib.sol";
import {MutualConsent} from "../utils/MutualConsent.sol";
import {InterestRateCredit} from "../modules/interest-rate/InterestRateCredit.sol";
import {LineOfCredit} from "../modules/credit/LineOfCredit.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";
import { SimpleOracle } from "../mock/SimpleOracle.sol";

interface Events {
    event Borrow(bytes32 indexed id, uint256 indexed amount);
}

contract LineTest is Test, Events{

    SimpleOracle oracle;
    address borrower;
    address arbiter;
    address lender;
    uint ttl = 150 days;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    LineOfCredit line;
    uint mintAmount = 100 ether;
    uint MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint minCollateralRatio = 1 ether; // 100%
    uint128 drawnRate = 100;
    uint128 facilityRate = 1;

    function setUp() public {
        borrower = address(10);
        arbiter = address(this);
        lender = address(20);

        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();

        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));

        line = new LineOfCredit(
            address(oracle),
            arbiter,
            borrower,
            ttl
        ); 
        assertEq(uint(line.init()), uint(LineLib.STATUS.ACTIVE));
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
        vm.prank(borrower);
        line.addCredit(drawnRate, facilityRate, amount, token, lender);
        vm.stopPrank();
        vm.prank(lender);
        line.addCredit(drawnRate, facilityRate, amount, token, lender);
        vm.stopPrank();
    }

    function setupQueueTest(uint amount) internal returns (address[] memory) {
      address[] memory tokens = new address[](amount);
      // generate token for simulating different repayment flows
      for(uint i = 0; i < amount; i++) {
        RevenueToken token = new RevenueToken();
        tokens[i] = address(token);

        token.mint(lender, mintAmount);
        token.mint(borrower, mintAmount);

        hoax(lender);
        token.approve(address(line), mintAmount);
        hoax(borrower);
        token.approve(address(line), mintAmount);

        

        
        oracle.changePrice(address(token), 1 ether);
       

        // add collateral for each token so we can borrow it during tests
        
        
      }
      
      return tokens;
    }

    function test_positions_move_in_queue_of_2() public {
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        hoax(lender);
        bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        hoax(lender);
        bytes32 id2 = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);

        assertEq(line.ids(0), id);
        assertEq(line.ids(1), id2);
        hoax(borrower);
        line.borrow(id2, 1 ether);
        
        assertEq(line.ids(0), id2);
        assertEq(line.ids(1), id);
        hoax(borrower);
        line.depositAndClose();

        assertEq(line.ids(0), id);
    }

    function test_positions_move_in_queue_of_4_random_active_line() public {
        
        address[] memory tokens = setupQueueTest(2);
        address token3 = tokens[0];
        address token4 = tokens[1];

        vm.startPrank(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);
        vm.stopPrank();
        
        vm.startPrank(lender);
        bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id2 = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        bytes32 id3 = line.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        bytes32 id4 = line.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);
        vm.stopPrank();

        assertEq(line.ids(0), id);
        assertEq(line.ids(1), id2);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id4);
        
        hoax(borrower);
        line.borrow(id2, 1 ether);
        
        assertEq(line.ids(0), id2);
        assertEq(line.ids(1), id);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id4);
        hoax(borrower);
        
        line.borrow(id4, 1 ether);
        
        assertEq(line.ids(0), id2);
        assertEq(line.ids(1), id4);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id); // id switches with id4, not just pushed one step back in queue
        hoax(borrower);
        line.depositAndClose();

        assertEq(line.ids(0), id4);
        assertEq(line.ids(1), id3);
        assertEq(line.ids(2), id);
    }



    // check that only borrowing from the last possible id will still sort queue properly
    // testing for bug in code where _i is initialized at 0 and never gets updated causing position to go to first position in repayment queue
    function test_positions_move_in_queue_of_4_only_last() public {
        vm.prank(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        vm.prank(lender);
        bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        vm.prank(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        vm.prank(lender);
        bytes32 id2 = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        
        address[] memory tokens = setupQueueTest(2);
        address token3 = tokens[0];
        address token4 = tokens[1];

        
        vm.prank(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        vm.prank(lender);
        bytes32 id3 = line.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        
        vm.prank(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);
        vm.prank(lender);
        bytes32 id4 = line.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);
        
        assertEq(line.ids(0), id);
        assertEq(line.ids(1), id2);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id4);
        
        vm.prank(borrower);
       
        line.borrow(id4, 1 ether);
        
        assertEq(line.ids(0), id4);
        assertEq(line.ids(1), id2);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id);
        
        vm.prank(borrower);
        line.borrow(id, 1 ether);

        assertEq(line.ids(0), id4);
        assertEq(line.ids(1), id);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id2); // id switches with id4, not just pushed one step back in queue

        vm.prank(borrower);
        line.depositAndRepay(1 wei);

        assertEq(line.ids(0), id4);
        assertEq(line.ids(1), id);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id2);

        vm.prank(borrower);
        line.depositAndClose();

        assertEq(line.ids(0), id);
        assertEq(line.ids(1), id3);
        assertEq(line.ids(2), id2);
    }

    // init

    function test_line_cant_init_after_init() public {
        vm.expectRevert(ILineOfCredit.AlreadyInitialized.selector);
        line.init();
    }

    function test_line_is_active_after_initializing() public {
        assertEq(uint(line.healthcheck()), uint(LineLib.STATUS.ACTIVE));
    }

     function test_line_is_uninitilized_on_deployment() public {
       
        LineOfCredit l = new LineOfCredit(
            address(oracle),
            arbiter,
            borrower,
            ttl
        );

        
        assertEq(uint(l.status()), uint(LineLib.STATUS.UNINITIALIZED));
    }

   // borrow/lend

   function test_can_add_credit_position() public {
        assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
        assertEq(supportedToken1.balanceOf(lender), mintAmount, "Contract should have initial mint balance");

        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);

        assert(id != bytes32(0));
        assertEq(supportedToken1.balanceOf(address(line)), 1 ether, "Line balance should be 1e18");
        assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Contract should have initial mint balance minus 1e18");
    }

    function test_can_add_credit_position_ETH() public {
        assertEq(address(line).balance, 0, "Line balance should be 0");
        assertEq(lender.balance, mintAmount, "lender should have initial mint balance");
        console.log(lender.balance);
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, Denominations.ETH, lender);

        vm.startPrank(lender);
        line.addCredit{value: 1 ether}(drawnRate, facilityRate, 1 ether, Denominations.ETH, lender);
        vm.stopPrank();
        console.log(lender.balance);
        bytes32 id = line.ids(0);
        assert(id != bytes32(0));
        assertEq(address(line).balance, 1 ether, "Line balance should be 1e18");
        assertEq(lender.balance, mintAmount - 1 ether, "Lender should have initial mint balance minus 1e18");
    }

    function test_can_borrow_within_credit_limit(uint amount) public {
        vm.assume(amount >= 1 ether && amount <= mintAmount);

        _addCredit(address(supportedToken1), amount);
        assertEq(supportedToken1.balanceOf(lender), mintAmount - amount, "Contract should have initial mint balance minus 1e18");
        bytes32 id = line.ids(0);

        assertEq(supportedToken1.balanceOf(address(line)), amount, "Line balance should be 1e18");

        hoax(borrower);
        line.borrow(id, amount);
        assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
        assertEq(supportedToken1.balanceOf(borrower), mintAmount + amount, "Contract should have initial mint balance");
        int prc = oracle.getLatestAnswer(address(supportedToken1));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        (uint p,) = line.updateOutstandingDebt();
        assertEq(p, (tokenPriceOneUnit * amount) / 1e18, "Principal should be set as one full unit price in USD");
    }

    function test_can_borrow_ETH(uint128 amount) public {
        vm.assume(amount >= 1 ether && amount <= mintAmount);

        vm.startPrank(borrower);
        line.addCredit(drawnRate, facilityRate, amount, Denominations.ETH, lender);
        vm.stopPrank();
        vm.startPrank(lender);
        line.addCredit{value: amount}(drawnRate, facilityRate, amount, Denominations.ETH, lender);
        vm.stopPrank();
        bytes32 id = line.ids(0);
        assert(id != bytes32(0));
        assertEq(address(line).balance, amount, "Line balance amount should be correct");
        assertEq(lender.balance, mintAmount - amount, "Contract should have initial mint balance minus 1e18");
        
        uint borrowAmount = amount * 25 / 1000;
        vm.startPrank(borrower);
        line.borrow(id, borrowAmount);
        vm.stopPrank();
        assertEq(address(line).balance, amount - borrowAmount, "Line balance should be 0");
        assertEq(borrower.balance, borrowAmount, "Borrower should have initial mint balance");

        int prc = oracle.getLatestAnswer(Denominations.ETH);
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        (uint p,) = line.updateOutstandingDebt();
        assertEq(p, (borrowAmount * tokenPriceOneUnit) / 1e18, "Principal should be set as one full unit price in USD");

    }

    function test_can_manually_close_if_no_outstanding_credit() public {

        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        hoax(borrower);
        line.depositAndRepay(1 ether);
        (uint p, uint i) = line.updateOutstandingDebt();
        assertEq(p + i, 0, "Line outstanding credit should be 0");
        hoax(borrower);
        line.close(id);
    }

    function test_can_repay_line() public {
        int prc = oracle.getLatestAnswer(address(supportedToken1));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);

        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        (uint p, uint i) = line.updateOutstandingDebt();
        assertEq(p + i, tokenPriceOneUnit, "Line outstanding credit should be set as one full unit price in USD");
        assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
        assertEq(i, 0, "No interest should have been accrued");
        hoax(borrower);
        line.depositAndRepay(1 ether);
        (uint p2, uint i2) = line.updateOutstandingDebt();
        assertEq(p2 + i2, 0, "Line outstanding credit should be 0");
        assertEq(p2, 0, "Principle should be 0");
        assertEq(i2, 0, "No interest should have been accrued");
    }

    function test_can_repay_part_of_line() public {
        int prc = oracle.getLatestAnswer(address(supportedToken1));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        hoax(borrower);
        line.depositAndRepay(0.5 ether);
        (uint p, uint i) = line.updateOutstandingDebt();
        assertEq(p + i, tokenPriceOneUnit / 2, "Line outstanding credit should be set as half of one full unit price in USD");
        assertEq(p, tokenPriceOneUnit / 2, "Principal should be set as half of one full unit price in USD");
        assertEq(i, 0, "No interest should have been accrued");
    }

    function test_can_repay_one_credit_and_keep_another() public {
        int prc = oracle.getLatestAnswer(address(supportedToken2));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        hoax(borrower);
        line.depositAndRepay(1 ether);

        _addCredit(address(supportedToken2), 1 ether);
        bytes32 id2 = line.ids(1);
        hoax(borrower);
        line.borrow(id2, 1 ether);
        (uint p, uint i) = line.updateOutstandingDebt();
        assertEq(p + i, tokenPriceOneUnit, "Line outstanding credit should be set as one full unit price in USD");
        assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
        assertEq(i, 0, "No interest should have been accrued");
    }

    function test_can_deposit_and_close_position() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        assertEq(supportedToken1.balanceOf(address(line)), 1 ether, "Line balance should be 1e18");
        hoax(borrower);
        line.borrow(id, 1 ether);
        assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
        assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Contract should have initial mint balance");
        hoax(borrower);
        line.depositAndClose();
        assertEq(supportedToken1.balanceOf(address(line)), 0, "Tokens should be sent back to lender");
        (uint p, uint i) = line.updateOutstandingDebt();
        assertEq(p + i, 0, "Line outstanding credit should be 0");
    }

    function test_can_withdraw_from_position() public {
        assertEq(supportedToken1.balanceOf(lender), mintAmount, "Contract should have initial mint balance");
         
        _addCredit(address(supportedToken1), 0.5 ether);
        bytes32 id = line.ids(0);
        assertEq(supportedToken1.balanceOf(lender), mintAmount - 0.5 ether, "Contract should have initial mint balance - 1e18 / 2");
        assertEq(supportedToken1.balanceOf(address(line)), 0.5 ether, "Line balance should be 1e18 / 2");
        hoax(lender);
        line.withdraw(id, 0.1 ether);
        assertEq(supportedToken1.balanceOf(address(line)), 0.4 ether, "Line balance should be 1e18 * 0.4");
        assertEq(supportedToken1.balanceOf(lender), mintAmount - 0.4 ether, "Contract should have initial mint balance - 1e18 * 0.4");
    }

    function test_return_lender_funds_on_deposit_and_close() public {
      assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
      assertEq(supportedToken1.balanceOf(lender), mintAmount, "Lender should have initial mint balance");
       
      _addCredit(address(supportedToken1), 1 ether);

      bytes32 id = line.ids(0);
      
      assert(id != bytes32(0));

      assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Lender should have initial balance less lent amount");

      // test depsoitAndClose()
      hoax(borrower);  
      line.borrow(id, 1 ether);

      assertEq(supportedToken1.balanceOf(borrower), mintAmount + 1 ether, "Borrower should have initial balance + loan");

      hoax(borrower);  
      line.depositAndClose();

      assertEq(supportedToken1.balanceOf(lender), mintAmount, "Lender should have initial balance after depositAndClose");
      assertEq(supportedToken1.balanceOf(address(line)), 0, "Line should not have tokens");
      
      assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID), "Line not repaid");
    }

    function test_return_lender_funds_on_close() public {
        assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
        assertEq(supportedToken1.balanceOf(lender), mintAmount, "Lender should have initial mint balance");
         
        _addCredit(address(supportedToken1), 1 ether);

        bytes32 id = line.ids(0);
        assert(id != bytes32(0));

        assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Lender should have initial balance less lent amount");
        
        hoax(borrower);
        line.borrow(id, 1 ether);
        assertEq(supportedToken1.balanceOf(borrower), mintAmount + 1 ether, "Borrower should have initial balance + loan");
        
        hoax(borrower);
        line.depositAndRepay(1 ether);
        assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Contract should have initial balance less lent amount");
        
        hoax(lender);
        line.close(id);

        assertEq(supportedToken1.balanceOf(lender), mintAmount, "Contract should have initial balance after close");
        assertEq(supportedToken1.balanceOf(address(line)), 0, "Line should not have tokens");
        assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID), "Line not repaid");
    }

    function test_accrues_and_repays_facility_fee_on_close() public {

        assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
        assertEq(supportedToken1.balanceOf(borrower), mintAmount, "Borrower should have initial mint balance");
        assertEq(supportedToken1.balanceOf(lender), mintAmount, "Lender should have initial mint balance");
        
     
        _addCredit(address(supportedToken1), 1 ether);
        
        bytes32 id = line.ids(0);
        
        assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Lender should have initial balance less lent amount");
        
        hoax(borrower);
        line.borrow(id, 1 ether);
        
        assertEq(supportedToken1.balanceOf(borrower), mintAmount + 1 ether, "Borrower should have initial balance plus borrowed amount");
        
        hoax(borrower);
        line.depositAndRepay(1 ether);

        assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Lender should have initial balance after depositAndClose");

        hoax(lender);
        line.close(id);

        assertEq(supportedToken1.balanceOf(lender), mintAmount, "Contract should have initial balance after close");
        assertEq(supportedToken1.balanceOf(address(line)), 0, "Line should not have tokens");
        assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID), "Line not repaid");
    }

    function test_cannot_open_credit_position_without_consent() public {
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
        assertEq(supportedToken1.balanceOf(borrower), mintAmount, "borrower balance should be original");
    }

    function test_cannot_borrow_from_nonexistant_position() public {
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        vm.expectRevert(ILineOfCredit.NoLiquidity.selector); 
        hoax(borrower);
        line.borrow(bytes32(uint(12743134)), 1 ether);
    }

    

    function test_cannot_withdraw_if_all_lineed_out() public {
         
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        vm.expectRevert(ILineOfCredit.NoLiquidity.selector); 
        hoax(lender);
        line.withdraw(id, 0.1 ether);
    }

    function test_cannot_borrow_more_than_position() public {
         
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        vm.expectRevert(ILineOfCredit.NoLiquidity.selector); 
        hoax(borrower);
        line.borrow(id, 100 ether);
    }

    function test_cannot_create_credit_with_tokens_unsupported_by_oracle() public {
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(unsupportedToken), lender);
        vm.expectRevert('SimpleOracle: unsupported token' ); 
        hoax(lender);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(unsupportedToken), lender);
    }


    function test_cannot_borrow_against_closed_position() public {
         
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
         
        _addCredit(address(supportedToken2), 1 ether);
        hoax(borrower);
        line.depositAndClose();
        vm.expectRevert(ILineOfCredit.NoLiquidity.selector);
        hoax(borrower);
        line.borrow(id, 1 ether);
    }

    function test_cannot_borrow_against_repaid_line() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        vm.startPrank(borrower);
        line.borrow(id, 1 ether);
        line.depositAndClose();
        vm.expectRevert(ILineOfCredit.NotActive.selector);
        line.borrow(id, 1 ether);
        vm.stopPrank();
    }

    function test_cannot_manually_close_if_debt_outstanding() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 0.1 ether);
        vm.expectRevert(ILineOfCredit.CloseFailedWithPrincipal.selector); 
        hoax(borrower);
        line.close(id);
    }

    function test_can_close_as_borrower() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 0.1 ether);
        vm.expectRevert(ILineOfCredit.CloseFailedWithPrincipal.selector); 
        hoax(borrower);
        line.close(id);
    }

    function test_can_close_as_lender() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 0.1 ether);
        
        vm.expectRevert(ILineOfCredit.CloseFailedWithPrincipal.selector); 
        hoax(lender);
        line.close(id);
    }



 



    function test_increase_credit_limit_with_consent() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        (uint d,,,,,,) = line.credits(id);
        
        hoax(borrower);
        line.increaseCredit(id, 1 ether);
        hoax(lender);
        line.increaseCredit(id, 1 ether);
        (uint d2,,,,,,) = line.credits(id);
        assertEq(d2 - d, 1 ether);
    }

    function test_cannot_increase_credit_limit_without_consent() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        (uint d,,,,,,) = line.credits(id);
        
        hoax(borrower);
        line.increaseCredit(id, 1 ether);
        hoax(address(0xdebf)); 
        vm.expectRevert(MutualConsent.Unauthorized.selector);
        line.increaseCredit(id, 1 ether);
    }

    function test_can_update_rates_with_consent() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
      
        hoax(borrower);
        line.setRates(id, uint128(1 ether), uint128(1 ether));
        hoax(lender);
        line.setRates(id, uint128(1 ether), uint128(1 ether));
        (uint128 drate, uint128 frate,) = line.interestRate().rates(id);
        assertEq(drate, uint128(1 ether));
        assertEq(frate, uint128(1 ether));
        assertGt(frate, facilityRate);
        assertGt(drate, drawnRate);
    }

    function test_cannot_update_rates_without_consent() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.setRates(id, uint128(1 ether), uint128(1 ether));
        vm.expectRevert(MutualConsent.Unauthorized.selector);
        hoax(address(0xdebf));
        line.setRates(id, uint128(1 ether), uint128(1 ether));
    }

    function test_health_becomes_liquidatable_if_debt_past_deadline() public {
        assert(line.healthcheck() == LineLib.STATUS.ACTIVE);
        // add line otherwise no debt == passed
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);

        vm.warp(ttl+1);
        assert(line.healthcheck() == LineLib.STATUS.LIQUIDATABLE);
    }

    function test_revert_if_borrowing_more_than_deposit(uint128 amount) public {
        amount = amount / 1e18;
        deal(address(supportedToken1), lender, amount);
        _addCredit(address(supportedToken1), amount);
        bytes32 id = line.ids(0);
        vm.expectRevert(ILineOfCredit.NoLiquidity.selector); 
        hoax(borrower);
        line.borrow(id, amount + 1);
    }
    
    function test_borrow_same_as_deposit(uint128 amount) public {
        vm.assume(amount > 0);
        amount /= 1e18;
        deal(address(supportedToken1), lender, amount);
        _addCredit(address(supportedToken1), amount);
        bytes32 id = line.ids(0);
        startHoax(borrower);
        vm.expectEmit(true, true, true, true);
        emit Borrow(id, amount);
        line.borrow(id, amount);
        vm.stopPrank();
    }

    function test_revert_no_token_price() public {
        oracle.changePrice(address(supportedToken1), -1);
        vm.startPrank(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        vm.stopPrank();
        vm.prank(lender);
        vm.expectRevert(CreditLib.NoTokenPrice.selector);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        vm.stopPrank();
    }

    function test_can_deposit_and_repay_from_multiple_accounts(uint256 credit) public {
        vm.assume(credit >= 1 ether && credit <= mintAmount);
        _addCredit(address(supportedToken1), credit);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, credit);
        uint256 repayAmount = (credit * 50) / 100;
        
        // bob repays
        address bob = makeAddr("bob");
        deal(address(supportedToken1), bob, repayAmount);
        startHoax(bob);
        supportedToken1.approve(address(line), repayAmount);
        line.depositAndRepay(repayAmount);
        vm.stopPrank();
        
        // sally repays
        address sally = makeAddr("sally");
        deal(address(supportedToken1), sally, repayAmount);
        startHoax(sally);
        supportedToken1.approve(address(line), repayAmount);
        line.depositAndRepay(repayAmount);
        vm.stopPrank();
        
        
        (uint256 p, uint256 i) = line.updateOutstandingDebt();
        assertEq(p + i, 0, "Line outstanding credit should be 0");
    }

    function test_deposit_and_repay_less_than_debt_becomes_liquidatable(uint credit) public {
        vm.assume(credit >= 1 ether && credit <= mintAmount);
        _addCredit(address(supportedToken1), credit);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, credit);

        hoax(borrower);
        line.depositAndRepay(credit - 1);

        vm.warp(line.deadline());

        assertEq(uint256(line.status()), uint256(LineLib.STATUS.ACTIVE));
        bool isSolvent = line.declareInsolvent();
        assertEq(uint256(line.status()), uint256(LineLib.STATUS.INSOLVENT));
        assertTrue(isSolvent);
    }
    
    function test_deposit_and_repay_debt_becomes_repaid(uint256 credit) public {
        vm.assume(credit >= 1 ether && credit <= mintAmount);
        _addCredit(address(supportedToken1), credit);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, credit);

        hoax(borrower);
        line.depositAndRepay(credit);

        vm.warp(line.deadline());

        hoax(borrower);
        line.close(id);
        assertEq(uint256(line.status()), uint256(LineLib.STATUS.REPAID));
    }

    // Uncomment to check gas limit threshhold for ids
    // function test_max_lenders_can_exist_before_contract_gets_bricked() public {
    //     for (uint maxPossible;; ++maxPossible) {
    //         address lender = address(uint160(maxPossible + 1));
    //         deal(lender, mintAmount);
    //         supportedToken1.mint(lender, mintAmount);

    //         vm.prank(borrower);
    //         line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);

    //         vm.startPrank(lender);
    //         supportedToken1.approve(address(line), MAX_INT);
    //         bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //         vm.stopPrank();

    //         vm.prank(borrower);
    //         try line.borrow(id, 1 ether) { //_sortQ forces array op
    //             emit log_named_bytes32('id', id);
    //         } catch {
    //             // position limit met
    //             emit log_named_uint('MAX LENDERS', maxPossible);
    //             return;
    //         }
    //     }
    // }

    function test_can_accrue_interest_after_deadline() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        (,,uint interestAccruedBefore,,,,) = line.credits(id);

        vm.warp(ttl+10 days);
        // accrue interest can be called after deadline
        line.accrueInterest();

        // check that accrued interest is saved to line credits
        (,,uint interestAccruedAfter,,,,) = line.credits(id);
        assertGt(interestAccruedAfter, interestAccruedBefore);
    }
}
