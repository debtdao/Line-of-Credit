pragma solidity 0.8.9;

import "forge-std/Test.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";

import { Spigot } from "../modules/spigot/Spigot.sol";
import { Escrow } from "../modules/escrow/Escrow.sol";
import { SecuredLine } from "../modules/credit/SecuredLine.sol";
import { ILineOfCredit } from "../interfaces/ILineOfCredit.sol";
import { ISecuredLine } from "../interfaces/ISecuredLine.sol";

import { LineLib } from "../utils/LineLib.sol";
import { MutualConsent } from "../utils/MutualConsent.sol";

import { MockLine } from "../mock/MockLine.sol";
import { SimpleOracle } from "../mock/SimpleOracle.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";

contract LineTest is Test {

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
    uint ttl = 150 days;

    address borrower;
    address arbiter;
    address lender;

    function setUp() public {
        borrower = address(20);
        lender = address(10);
        arbiter = address(this);
        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();

        spigot = new Spigot(arbiter, borrower, borrower);
        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));

        escrow = new Escrow(minCollateralRatio, address(oracle), arbiter, borrower);

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
        
        escrow.updateLine(address(line));
        spigot.updateOwner(address(line));
        
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
        line.addCredit(drawnRate, facilityRate, amount, token, lender);
        vm.stopPrank();
        hoax(lender);
        line.addCredit(drawnRate, facilityRate, amount, token, lender);
        vm.stopPrank();
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
        assertEq(balanceOfEscrow, supportedToken1.balanceOf(address(escrow)) + 1 ether, "Escrow balance should have increased by 1e18");
        assertEq(balanceOfArbiter, supportedToken2.balanceOf(arbiter) - 1 ether, "Arbiter balance should have decreased by 1e18");
        
    }

    function test_line_is_uninitilized_on_deployment() public {
        Spigot s = new Spigot(arbiter, borrower, borrower);
        Escrow e = new Escrow(minCollateralRatio, address(oracle), arbiter, borrower);
        SecuredLine l = new SecuredLine(
            address(oracle),
            arbiter,
            borrower,
            payable(address(0)),
            address(s),
            address(e),
            150 days,
            0
        );
        assertEq(uint(l.init()), uint(LineLib.STATUS.UNINITIALIZED));
    }

    function invariant_position_count_equals_non_null_ids() public {
        (uint c, uint l) = line.counts();
        uint count = 0;
        for(uint i = 0; i < l;) {
          if(line.ids(i) != bytes32(0)) { unchecked { ++count; } }
          unchecked { ++i; }
        }
        assertEq(c, count);
    }

    function test_line_is_uninitilized_if_escrow_not_owned() public {
        address mock = address(new MockLine(0, address(3)));
        Spigot s = new Spigot(arbiter, borrower, borrower);
        Escrow e = new Escrow(minCollateralRatio, address(oracle), mock, borrower);
        SecuredLine l = new SecuredLine(
            address(oracle),
            arbiter,
            borrower,
            payable(address(0)),
            address(s),
            address(e),
            150 days,
            0
        );

        // configure other modules
        s.updateOwner(address(l));
        
        assertEq(uint(l.init()), uint(LineLib.STATUS.UNINITIALIZED));
    }

    function test_line_is_uninitilized_if_spigot_not_owned() public {
        Spigot s = new Spigot(arbiter, borrower, borrower);
        Escrow e = new Escrow(minCollateralRatio, address(oracle), address(this), borrower);
        SecuredLine l = new SecuredLine(
            address(oracle),
            arbiter,
            borrower,
            payable(address(0)),
            address(s),
            address(e),
            150 days,
            0
        );

        // configure other modules
        e.updateLine(address(l));
        
        assertEq(uint(l.init()), uint(LineLib.STATUS.UNINITIALIZED));
    }


    // function test_line_cant_init_after_init() public {
    //     vm.expectRevert(ILineOfCredit.AlreadyInitialized.selector);
    //     line.init();
    // }

    // function test_line_is_active_after_initializing() public {
    //     assertEq(uint(line.healthcheck()), uint(LineLib.STATUS.ACTIVE));
    // }

    // function test_can_add_credit_position() public {
    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount, "Contract should have initial mint balance");

    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);

    //     assert(id != bytes32(0));
    //     assertEq(supportedToken1.balanceOf(address(line)), 1 ether, "Line balance should be 1e18");
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Contract should have initial mint balance minus 1e18");
    // }

    // function test_can_add_credit_position_ETH() public {
    //     assertEq(address(line).balance, 0, "Line balance should be 0");
    //     assertEq(lender.balance, mintAmount, "lender should have initial mint balance");
    //     console.log(lender.balance);
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, Denominations.ETH, lender);

    //     vm.startPrank(lender);
    //     line.addCredit{value: 1 ether}(drawnRate, facilityRate, 1 ether, Denominations.ETH, lender);
    //     vm.stopPrank();
    //     console.log(lender.balance);
    //     bytes32 id = line.ids(0);
    //     assert(id != bytes32(0));
    //     assertEq(address(line).balance, 1 ether, "Line balance should be 1e18");
    //     assertEq(lender.balance, mintAmount - 1 ether, "Lender should have initial mint balance minus 1e18");
    // }

    // function test_can_borrow() public {

    //     _addCredit(address(supportedToken1), 1 ether);
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Contract should have initial mint balance minus 1e18");
    //     bytes32 id = line.ids(0);

    //     assertEq(supportedToken1.balanceOf(address(line)), 1 ether, "Line balance should be 1e18");

    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
    //     assertEq(supportedToken1.balanceOf(borrower), mintAmount + 1 ether, "Contract should have initial mint balance");
    //     int prc = oracle.getLatestAnswer(address(supportedToken1));
    //     uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
    //     (uint p,) = line.updateOutstandingDebt();
    //     assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
    // }

    // function test_can_borrow_ETH() public {
    //     vm.startPrank(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, Denominations.ETH, lender);
    //     vm.stopPrank();
    //     vm.startPrank(lender);
    //     line.addCredit{value: 1 ether}(drawnRate, facilityRate, 1 ether, Denominations.ETH, lender);
    //     vm.stopPrank();
    //     bytes32 id = line.ids(0);
    //     assert(id != bytes32(0));
    //     assertEq(address(line).balance, 1 ether, "Line balance should be 1e18");
    //     assertEq(lender.balance, mintAmount - 1 ether, "Contract should have initial mint balance minus 1e18");
        
    //     vm.startPrank(borrower);
    //     line.borrow(id, 0.01 ether);
    //     vm.stopPrank();
    //     assertEq(address(line).balance, 0.99 ether, "Line balance should be 0");
    //     assertEq(borrower.balance,  0.01 ether, "Borrower should have initial mint balance");

    //     int prc = oracle.getLatestAnswer(Denominations.ETH);
    //     uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
    //     (uint p,) = line.updateOutstandingDebt();
    //     assertEq(p, tokenPriceOneUnit / 100, "Principal should be set as one full unit price in USD");

    // }

    // function test_can_manually_close_if_no_outstanding_credit() public {

    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     hoax(borrower);
    //     line.depositAndRepay(1 ether);
    //     (uint p, uint i) = line.updateOutstandingDebt();
    //     assertEq(p + i, 0, "Line outstanding credit should be 0");
    //     hoax(borrower);
    //     line.close(id);
    // }

    // function test_can_repay_line() public {
    //     int prc = oracle.getLatestAnswer(address(supportedToken1));
    //     uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);

    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     (uint p, uint i) = line.updateOutstandingDebt();
    //     assertEq(p + i, tokenPriceOneUnit, "Line outstanding credit should be set as one full unit price in USD");
    //     assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
    //     assertEq(i, 0, "No interest should have been accrued");
    //     hoax(borrower);
    //     line.depositAndRepay(1 ether);
    //     (uint p2, uint i2) = line.updateOutstandingDebt();
    //     assertEq(p2 + i2, 0, "Line outstanding credit should be 0");
    //     assertEq(p2, 0, "Principle should be 0");
    //     assertEq(i2, 0, "No interest should have been accrued");
    // }

    // function test_can_repay_part_of_line() public {
    //     int prc = oracle.getLatestAnswer(address(supportedToken1));
    //     uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     hoax(borrower);
    //     line.depositAndRepay(0.5 ether);
    //     (uint p, uint i) = line.updateOutstandingDebt();
    //     assertEq(p + i, tokenPriceOneUnit / 2, "Line outstanding credit should be set as half of one full unit price in USD");
    //     assertEq(p, tokenPriceOneUnit / 2, "Principal should be set as half of one full unit price in USD");
    //     assertEq(i, 0, "No interest should have been accrued");
    // }

    // function test_can_repay_one_credit_and_keep_another() public {
    //     int prc = oracle.getLatestAnswer(address(supportedToken2));
    //     uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     hoax(borrower);
    //     line.depositAndRepay(1 ether);

    //     _addCredit(address(supportedToken2), 1 ether);
    //     bytes32 id2 = line.ids(1);
    //     hoax(borrower);
    //     line.borrow(id2, 1 ether);
    //     (uint p, uint i) = line.updateOutstandingDebt();
    //     assertEq(p + i, tokenPriceOneUnit, "Line outstanding credit should be set as one full unit price in USD");
    //     assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
    //     assertEq(i, 0, "No interest should have been accrued");
    // }


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

        hoax(lender);
        token.approve(address(escrow), mintAmount);

        hoax(borrower);
        token.approve(address(escrow), mintAmount);
        oracle.changePrice(address(token), 1 ether);
        escrow.enableCollateral(address(token));

        // add collateral for each token so we can borrow it during tests
        hoax(borrower);
        escrow.addCollateral(1 ether, address(token));
      }
      
      return tokens;
    }

    // function test_positions_move_in_queue_of_2() public {
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     hoax(lender);
    //     bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
    //     hoax(lender);
    //     bytes32 id2 = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);

    //     assertEq(line.ids(0), id);
    //     assertEq(line.ids(1), id2);
    //     hoax(borrower);
    //     line.borrow(id2, 1 ether);
        
    //     assertEq(line.ids(0), id2);
    //     assertEq(line.ids(1), id);
    //     hoax(borrower);
    //     line.depositAndClose();

    //     assertEq(line.ids(0), id);
    // }

    // function test_positions_move_in_queue_of_4_random_active_line() public {
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     hoax(lender);
    //     bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
    //     hoax(lender);
    //     bytes32 id2 = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);

    //     // create 3rd token to fully test array sorting
    //     address[] memory tokens = setupQueueTest(2);
    //     address token3 = tokens[0];
    //     address token4 = tokens[1];

    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
    //     hoax(lender);
    //     bytes32 id3 = line.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);
    //     hoax(lender);
    //     bytes32 id4 = line.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);

    //     assertEq(line.ids(0), id);
    //     assertEq(line.ids(1), id2);
    //     assertEq(line.ids(2), id3);
    //     assertEq(line.ids(3), id4);
    //     hoax(borrower);
    //     line.borrow(id2, 1 ether);
        
    //     assertEq(line.ids(0), id2);
    //     assertEq(line.ids(1), id);
    //     assertEq(line.ids(2), id3);
    //     assertEq(line.ids(3), id4);
    //     hoax(borrower);
    //     line.borrow(id4, 1 ether);

    //     assertEq(line.ids(0), id2);
    //     assertEq(line.ids(1), id4);
    //     assertEq(line.ids(2), id3);
    //     assertEq(line.ids(3), id); // id switches with id4, not just pushed one step back in queue
    //     hoax(borrower);
    //     line.depositAndClose();

    //     assertEq(line.ids(0), id4);
    //     assertEq(line.ids(1), id3);
    //     assertEq(line.ids(2), id);
    // }



    // // check that only borrowing from the last possible id will still sort queue properly
    // // testing for bug in code where _i is initialized at 0 and never gets updated causing position to go to first position in repayment queue
    // function test_positions_move_in_queue_of_4_only_last() public {
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     hoax(lender);
    //     bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
    //     hoax(lender);
    //     bytes32 id2 = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);

    //     address[] memory tokens = setupQueueTest(2);
    //     address token3 = tokens[0];
    //     address token4 = tokens[1];


    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
    //     hoax(lender);
    //     bytes32 id3 = line.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);
    //     hoax(lender);
    //     bytes32 id4 = line.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);

    //     assertEq(line.ids(0), id);
    //     assertEq(line.ids(1), id2);
    //     assertEq(line.ids(2), id3);
    //     assertEq(line.ids(3), id4);

    //     hoax(borrower);
    //     line.borrow(id4, 1 ether);
        
    //     assertEq(line.ids(0), id4);
    //     assertEq(line.ids(1), id2);
    //     assertEq(line.ids(2), id3);
    //     assertEq(line.ids(3), id);
        
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);

    //     assertEq(line.ids(0), id4);
    //     assertEq(line.ids(1), id);
    //     assertEq(line.ids(2), id3);
    //     assertEq(line.ids(3), id2); // id switches with id4, not just pushed one step back in queue

    //     hoax(borrower);
    //     line.depositAndRepay(1 wei);

    //     assertEq(line.ids(0), id4);
    //     assertEq(line.ids(1), id);
    //     assertEq(line.ids(2), id3);
    //     assertEq(line.ids(3), id2);

    //     hoax(borrower);
    //     line.depositAndClose();

    //     assertEq(line.ids(0), id);
    //     assertEq(line.ids(1), id3);
    //     assertEq(line.ids(2), id2);
    // }

    // function test_can_deposit_and_close_position() public {
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     assertEq(supportedToken1.balanceOf(address(line)), 1 ether, "Line balance should be 1e18");
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Contract should have initial mint balance");
    //     hoax(borrower);
    //     line.depositAndClose();
    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Tokens should be sent back to lender");
    //     (uint p, uint i) = line.updateOutstandingDebt();
    //     assertEq(p + i, 0, "Line outstanding credit should be 0");
    // }

    // function test_can_withdraw_from_position() public {
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount, "Contract should have initial mint balance");
         
    //     _addCredit(address(supportedToken1), 0.5 ether);
    //     bytes32 id = line.ids(0);
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 0.5 ether, "Contract should have initial mint balance - 1e18 / 2");
    //     assertEq(supportedToken1.balanceOf(address(line)), 0.5 ether, "Line balance should be 1e18 / 2");
    //     hoax(lender);
    //     line.withdraw(id, 0.1 ether);
    //     assertEq(supportedToken1.balanceOf(address(line)), 0.4 ether, "Line balance should be 1e18 * 0.4");
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 0.4 ether, "Contract should have initial mint balance - 1e18 * 0.4");
    // }

    // function test_return_lender_funds_on_deposit_and_close() public {
    //   assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
    //   assertEq(supportedToken1.balanceOf(lender), mintAmount, "Lender should have initial mint balance");
       
    //   _addCredit(address(supportedToken1), 1 ether);

    //   bytes32 id = line.ids(0);
      
    //   assert(id != bytes32(0));

    //   assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Lender should have initial balance less lent amount");

    //   // test depsoitAndClose()
    //   hoax(borrower);  
    //   line.borrow(id, 1 ether);

    //   assertEq(supportedToken1.balanceOf(borrower), mintAmount + 1 ether, "Borrower should have initial balance + loan");

    //   hoax(borrower);  
    //   line.depositAndClose();

    //   assertEq(supportedToken1.balanceOf(lender), mintAmount, "Lender should have initial balance after depositAndClose");
    //   assertEq(supportedToken1.balanceOf(address(line)), 0, "Line should not have tokens");
      
    //   assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID), "Line not repaid");
    // }

    // function test_return_lender_funds_on_close() public {
    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount, "Lender should have initial mint balance");
         
    //     _addCredit(address(supportedToken1), 1 ether);

    //     bytes32 id = line.ids(0);
    //     assert(id != bytes32(0));

    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Lender should have initial balance less lent amount");
        
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     assertEq(supportedToken1.balanceOf(borrower), mintAmount + 1 ether, "Borrower should have initial balance + loan");
        
    //     hoax(borrower);
    //     line.depositAndRepay(1 ether);
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Contract should have initial balance less lent amount");
        
    //     hoax(lender);
    //     line.close(id);

    //     assertEq(supportedToken1.balanceOf(lender), mintAmount, "Contract should have initial balance after close");
    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Line should not have tokens");
    //     assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID), "Line not repaid");
    // }

    // function test_accrues_and_repays_facility_fee_on_close() public {

    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
    //     assertEq(supportedToken1.balanceOf(borrower), mintAmount, "Borrower should have initial mint balance");
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount, "Lender should have initial mint balance");
        
     
    //     _addCredit(address(supportedToken1), 1 ether);
        
    //     bytes32 id = line.ids(0);
        
    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Lender should have initial balance less lent amount");
        
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
        
    //     assertEq(supportedToken1.balanceOf(borrower), mintAmount + 1 ether, "Borrower should have initial balance plus borrowed amount");
        
    //     hoax(borrower);
    //     line.depositAndRepay(1 ether);

    //     assertEq(supportedToken1.balanceOf(lender), mintAmount - 1 ether, "Lender should have initial balance after depositAndClose");

    //     hoax(lender);
    //     line.close(id);

    //     assertEq(supportedToken1.balanceOf(lender), mintAmount, "Contract should have initial balance after close");
    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Line should not have tokens");
    //     assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID), "Line not repaid");
    // }

    // function test_cannot_open_credit_position_without_consent() public {
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     assertEq(supportedToken1.balanceOf(address(line)), 0, "Line balance should be 0");
    //     assertEq(supportedToken1.balanceOf(borrower), mintAmount, "borrower balance should be original");
    // }

    // function test_cannot_borrow_from_nonexistant_position() public {
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     vm.expectRevert(ILineOfCredit.NoLiquidity.selector); 
    //     hoax(borrower);
    //     line.borrow(bytes32(uint(12743134)), 1 ether);
    // }

    function test_cannot_borrow_from_credit_position_if_under_collateralised() public {
         
        _addCredit(address(supportedToken1), 100 ether);
        bytes32 id = line.ids(0);
        vm.expectRevert(ILineOfCredit.NotActive.selector); 
        hoax(borrower);
        line.borrow(id, 100 ether);
    }

    // function test_cannot_withdraw_if_all_lineed_out() public {
         
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     vm.expectRevert(ILineOfCredit.NoLiquidity.selector); 
    //     hoax(lender);
    //     line.withdraw(id, 0.1 ether);
    // }

    // function test_cannot_borrow_more_than_position() public {
         
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     vm.expectRevert(ILineOfCredit.NoLiquidity.selector); 
    //     hoax(borrower);
    //     line.borrow(id, 100 ether);
    // }

    // function test_cannot_create_credit_with_tokens_unsupported_by_oracle() public {
    //     hoax(borrower);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(unsupportedToken), lender);
    //     vm.expectRevert('SimpleOracle: unsupported token' ); 
    //     hoax(lender);
    //     line.addCredit(drawnRate, facilityRate, 1 ether, address(unsupportedToken), lender);
    // }

    function test_cannot_borrow_if_not_active() public {
        assert(line.healthcheck() == LineLib.STATUS.ACTIVE);
         
        _addCredit(address(supportedToken1), 0.1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 0.1 ether);
        oracle.changePrice(address(supportedToken2), 1);
        assert(line.healthcheck() == LineLib.STATUS.LIQUIDATABLE);
        vm.expectRevert(ILineOfCredit.NotActive.selector); 
        hoax(borrower);
        line.borrow(id, 0.9 ether);
    }

    // function test_cannot_borrow_against_closed_position() public {
         
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
         
    //     _addCredit(address(supportedToken2), 1 ether);
    //     hoax(borrower);
    //     line.depositAndClose();
    //     vm.expectRevert(ILineOfCredit.NoLiquidity.selector);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    // }

    // function test_cannot_borrow_against_repaid_line() public {
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     vm.startPrank(borrower);
    //     line.borrow(id, 1 ether);
    //     line.depositAndClose();
    //     vm.expectRevert(ILineOfCredit.NotActive.selector);
    //     line.borrow(id, 1 ether);
    //     vm.stopPrank();
    // }

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

    // Liquidate  / Liquidatable

    // function test_must_be_in_debt_to_liquidate() public {
    //     vm.expectRevert(ILineOfCredit.NotBorrowing.selector);
    //     line.liquidate(1 ether, address(supportedToken2));
    // }

    // function test_health_becomes_liquidatable_if_cratio_below_min() public {
    //     assertEq(uint(line.healthcheck()), uint(LineLib.STATUS.ACTIVE));
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);
    //     oracle.changePrice(address(supportedToken2), 1);
    //     assertEq(uint(line.healthcheck()), uint(LineLib.STATUS.LIQUIDATABLE));
    // }

    // function test_health_becomes_liquidatable_if_debt_past_deadline() public {
    //     assert(line.healthcheck() == LineLib.STATUS.ACTIVE);
    //     // add line otherwise no debt == passed
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.borrow(id, 1 ether);

    //     vm.warp(ttl+1);
    //     assert(line.healthcheck() == LineLib.STATUS.LIQUIDATABLE);
    // }

    function test_cannot_liquidate_if_no_debt_when_deadline_passes() public {
        hoax(arbiter);
        vm.warp(ttl+1);
        vm.expectRevert(ILineOfCredit.NotBorrowing.selector); 
        line.liquidate(1 ether, address(supportedToken2));
    }

    function test_can_liquidate_if_debt_when_deadline_passes() public {
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        hoax(lender);
        bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        hoax(borrower);
        line.borrow(id, 1 ether);

        vm.warp(ttl + 1);
        line.liquidate(0.9 ether, address(supportedToken2));
    }

    function test_cannot_liquidate_escrow_if_cratio_above_min() public {
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        hoax(lender);
        bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        hoax(borrower);
        line.borrow(id, 1 ether);

        vm.expectRevert(ILineOfCredit.NotLiquidatable.selector); 
        line.liquidate(1 ether, address(supportedToken2));
    }

    function test_health_is_not_liquidatable_if_cratio_above_min() public {
        assertTrue(line.healthcheck() != LineLib.STATUS.LIQUIDATABLE);
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


    function test_health_becomes_liquidatable_when_cratio_below_min() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);
        oracle.changePrice(address(supportedToken2), 1);
        assert(line.healthcheck() == LineLib.STATUS.LIQUIDATABLE);
    }

    function test_cannot_liquidate_as_anon() public {
        hoax(borrower);
        line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        hoax(lender);
        bytes32 id = line.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        hoax(borrower);
        line.borrow(id, 1 ether);

        hoax(address(0xdead));
        vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector); 
        line.liquidate(1 ether, address(supportedToken2));
    }

    function test_cannot_liquidate_as_borrower() public {
        // TODO update stakeholders to be different addresses
        // hoax(borrower);
        // vm.warp(ttl+1);
        // vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector); 
        // line.liquidate(1 ether, address(supportedToken2));
    }


    // function test_increase_credit_limit_with_consent() public {
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     (uint d,,,,,,) = line.credits(id);
        
    //     hoax(borrower);
    //     line.increaseCredit(id, 1 ether);
    //     hoax(lender);
    //     line.increaseCredit(id, 1 ether);
    //     (uint d2,,,,,,) = line.credits(id);
    //     assertEq(d2 - d, 1 ether);
    // }

    // function test_cannot_increase_credit_limit_without_consent() public {
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     (uint d,,,,,,) = line.credits(id);
        
    //     hoax(borrower);
    //     line.increaseCredit(id, 1 ether);
    //     hoax(address(0xdebf)); 
    //     vm.expectRevert(MutualConsent.Unauthorized.selector);
    //     line.increaseCredit(id, 1 ether);
    // }

    // function test_can_update_rates_with_consent() public {
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
      
    //     hoax(borrower);
    //     line.setRates(id, uint128(1 ether), uint128(1 ether));
    //     hoax(lender);
    //     line.setRates(id, uint128(1 ether), uint128(1 ether));
    //     (uint128 drate, uint128 frate,) = line.interestRate().rates(id);
    //     assertEq(drate, uint128(1 ether));
    //     assertEq(frate, uint128(1 ether));
    //     assertGt(frate, facilityRate);
    //     assertGt(drate, drawnRate);
    // }

    // function test_cannot_update_rates_without_consent() public {
    //     _addCredit(address(supportedToken1), 1 ether);
    //     bytes32 id = line.ids(0);
    //     hoax(borrower);
    //     line.setRates(id, uint128(1 ether), uint128(1 ether));
    //     vm.expectRevert(MutualConsent.Unauthorized.selector);
    //     hoax(address(0xdebf));
    //     line.setRates(id, uint128(1 ether), uint128(1 ether));
    // }


// declareInsolvent
    function test_must_be_in_debt_to_go_insolvent() public {
        vm.expectRevert(ILineOfCredit.NotBorrowing.selector);
        line.declareInsolvent();
    }

    function test_only_arbiter_can_delcare_insolvency() public {
        _addCredit(address(supportedToken1), 1 ether);

        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);

        hoax(address(0xdebf));
        vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
        line.declareInsolvent();
    }

    function test_cant_delcare_insolvency_if_not_liquidatable() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);

        hoax(arbiter);
        vm.expectRevert(ILineOfCredit.NotLiquidatable.selector);
        line.declareInsolvent();
    }



    function test_cannot_insolve_until_liquidate_all_escrowed_tokens() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);

        vm.warp(ttl+1);

        hoax(arbiter);

        // ensure spigot insolvency check passes
        assertTrue(line.releaseSpigot());
        // "sell" spigot off
        line.spigot().updateOwner(address(0xf1c0));

        assertEq(0.9 ether, line.liquidate(0.9 ether, address(supportedToken2)));

        vm.expectRevert(
          abi.encodeWithSelector(ILineOfCredit.NotInsolvent.selector, line.escrow())
        );
        line.declareInsolvent();
    }

    function test_cannot_insolve_until_liquidate_spigot() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.borrow(id, 1 ether);

        vm.warp(ttl+1);
        hoax(arbiter);
        // ensure escrow insolvency check passes
        assertEq(1 ether, line.liquidate(1 ether, address(supportedToken2)));

        vm.expectRevert(
          abi.encodeWithSelector(ILineOfCredit.NotInsolvent.selector, line.spigot())
        );

        line.declareInsolvent();
    }

    function test_can_delcare_insolvency_when_all_assets_liquidated() public {
        _addCredit(address(supportedToken1), 1 ether);
        bytes32 id = line.ids(0);
        hoax(borrower);
        
        line.borrow(id, 1 ether);
        console.log('check');

        vm.warp(ttl+1);
        //hoax(arbiter);
        
        assertTrue(line.releaseSpigot());
        assertTrue(line.spigot().updateOwner(address(0xf1c0)));
        assertEq(1 ether, line.liquidate(1 ether, address(supportedToken2)));
        // release spigot + liquidate
        
        line.declareInsolvent();
        assertEq(uint(LineLib.STATUS.INSOLVENT), uint(line.status()));
    }


    // Rollover()

    function test_cant_rollover_if_not_repaid() public {
      // ACTIVE w/o debt
      vm.expectRevert(ISecuredLine.DebtOwed.selector);
      hoax(borrower);
      line.rollover(address(line));

      // ACTIVE w/ debt
      _addCredit(address(supportedToken1), 1 ether);
      bytes32 id = line.ids(0);
      hoax(borrower);
      line.borrow(id, 1 ether);

      vm.expectRevert(ISecuredLine.DebtOwed.selector);
      hoax(borrower);
      line.rollover(address(line));

      oracle.changePrice(address(supportedToken2), 1);
      assertFalse(line.status() == LineLib.STATUS.REPAID);
      // assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID));

      // LIQUIDATABLE w/ debt
      vm.expectRevert(ISecuredLine.DebtOwed.selector);
      hoax(borrower);
      line.rollover(address(line));
      hoax(borrower);
      line.depositAndClose();
      
      // REPAID (test passes if next error)
      vm.expectRevert(ILineOfCredit.AlreadyInitialized.selector);
      hoax(borrower);
      line.rollover(address(line));
    }

    function test_cant_rollover_if_newLine_already_initialized() public {
      _addCredit(address(supportedToken1), 1 ether);
      bytes32 id = line.ids(0);
      hoax(borrower);
      line.borrow(id, 1 ether);
      hoax(borrower);
      line.depositAndClose();
      
      // create and init new line with new modules
      Spigot s = new Spigot(arbiter, borrower, borrower);
      Escrow e = new Escrow(minCollateralRatio, address(oracle), arbiter, borrower);
      SecuredLine l = new SecuredLine(
        address(oracle),
        arbiter,
        borrower,
        payable(address(0)),
        address(s),
        address(e),
        150 days,
        0
      );

      e.updateLine(address(l));
      s.updateOwner(address(l));
      l.init();

      // giving our modules should fail because taken already
      vm.expectRevert(ILineOfCredit.AlreadyInitialized.selector);
      hoax(borrower);
      line.rollover(address(l));
    }

    function test_cant_rollover_if_newLine_not_line() public {
      _addCredit(address(supportedToken1), 1 ether);
      bytes32 id = line.ids(0);
      hoax(borrower);
      line.borrow(id, 1 ether);
      hoax(borrower);
      line.depositAndClose();

      vm.expectRevert(); // evm revert, .init() does not exist on address(this)
      hoax(borrower);
      line.rollover(address(this));
    }


   function test_cant_rollover_if_not_borrower() public {
      hoax(address(0xdeaf));
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.rollover(arbiter);
    }

    function test_rollover_gives_modules_to_new_line() public {
      _addCredit(address(supportedToken1), 1 ether);
      bytes32 id = line.ids(0);
      hoax(borrower);
      line.borrow(id, 1 ether);

      hoax(borrower);
      line.depositAndClose();

      SecuredLine l = new SecuredLine(
        address(oracle),
        arbiter,
        borrower,
        payable(address(0)),
        address(spigot),
        address(escrow),
        150 days,
        0
      );
      hoax(borrower);
      line.rollover(address(l));

      assertEq(address(l.spigot()) , address(spigot));
      assertEq(address(l.escrow()) , address(escrow));
    }
    receive() external payable {}
}
