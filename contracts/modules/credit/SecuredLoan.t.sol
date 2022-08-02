pragma solidity 0.8.9;

import { Escrow } from "../escrow/Escrow.sol";
import { DSTest } from  "../../../lib/ds-test/src/test.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { RevenueToken } from "../../mock/RevenueToken.sol";
import { SimpleOracle } from "../../mock/SimpleOracle.sol";
import { SecuredLoan } from "./SecuredLoan.sol";

contract LoanTest is DSTest {

    Escrow escrow;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    SimpleOracle oracle;
    SecuredLoan loan;
    uint mintAmount = 100 ether;
    uint MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint minCollateralRatio = 1 ether; // 100%
    uint128 drawnRate = 100;
    uint128 facilityRate = 1;

    address borrower;
    address arbiter;
    address lender;

    function setUp() public {
        borrower = address(this);
        lender = address(this);
        arbiter = address(this);
        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();
        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));
        loan = new SecuredLoan(address(oracle), arbiter, borrower, address(0), 1 ether, 150 days, 0);
        escrow = loan.escrow();
        escrow.enableCollateral( address(supportedToken1));
        escrow.enableCollateral( address(supportedToken2));
        _mintAndApprove();
        escrow.addCollateral(1 ether, address(supportedToken2));
    }

    function _mintAndApprove() internal {
        supportedToken1.mint(borrower, mintAmount);
        supportedToken1.approve(address(escrow), MAX_INT);
        supportedToken1.approve(address(loan), MAX_INT);
        supportedToken2.mint(borrower, mintAmount);
        supportedToken2.approve(address(escrow), MAX_INT);
        supportedToken2.approve(address(loan), MAX_INT);
        unsupportedToken.mint(borrower, mintAmount);
        unsupportedToken.approve(address(escrow), MAX_INT);
        unsupportedToken.approve(address(loan), MAX_INT);
    }

    function test_can_liquidate_escrow_if_cratio_below_min() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        uint balanceOfEscrow = supportedToken2.balanceOf(address(escrow));
        uint balanceOfArbiter = supportedToken2.balanceOf(arbiter);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertGt(p, 0);
        oracle.changePrice(address(supportedToken2), 1);
        loan.liquidate(id, 1 ether, address(supportedToken2));
        assertEq(balanceOfEscrow, supportedToken1.balanceOf(address(escrow)) + 1 ether, "Escrow balance should have increased by 1e18");
        assertEq(balanceOfArbiter, supportedToken2.balanceOf(arbiter) - 1 ether, "Arbiter balance should have decreased by 1e18");
    }

    function test_health_becomes_liquidatable_if_cratio_below_min() public {
        assert(loan.healthcheck() == LoanLib.STATUS.ACTIVE);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        oracle.changePrice(address(supportedToken2), 1);
        assert(loan.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
    }

    function test_loan_is_active_on_deployment() public {
        assert(loan.healthcheck() == LoanLib.STATUS.ACTIVE);
    }

    function test_can_add_credit_position() public {
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan balance should be 0");
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial mint balance");
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        assert(id != bytes32(0));
        assertEq(supportedToken1.balanceOf(address(loan)), 1 ether, "Loan balance should be 1e18");
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 1 ether, "Contract should have initial mint balance minus 1e18");
    }

    function test_can_borrow() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 1 ether, "Contract should have initial mint balance minus 1e18");
        bytes32 id = loan.ids(0);
        assertEq(supportedToken1.balanceOf(address(loan)), 1 ether, "Loan balance should be 1e18");
        loan.borrow(id, 1 ether);
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan balance should be 0");
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial mint balance");
        int prc = oracle.getLatestAnswer(address(supportedToken1));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        (uint p,) = loan.updateOutstandingDebt();
        assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
    }

    function test_can_manually_close_if_no_outstanding_credit() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        loan.depositAndRepay(1 ether);
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertEq(p + i, 0, "Loan outstanding credit should be 0");
        loan.close(id);
    }

    function test_can_repay_loan() public {
        int prc = oracle.getLatestAnswer(address(supportedToken1));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertEq(p + i, tokenPriceOneUnit, "Loan outstanding credit should be set as one full unit price in USD");
        assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
        assertEq(i, 0, "No interest should have been accrued");
        loan.depositAndRepay(1 ether);
        (uint p2, uint i2) = loan.updateOutstandingDebt();
        assertEq(p2 + i2, 0, "Loan outstanding credit should be 0");
        assertEq(p2, 0, "Principle should be 0");
        assertEq(i2, 0, "No interest should have been accrued");
    }

    function test_can_repay_part_of_loan() public {
        int prc = oracle.getLatestAnswer(address(supportedToken1));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        loan.depositAndRepay(0.5 ether);
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertEq(p + i, tokenPriceOneUnit / 2, "Loan outstanding credit should be set as half of one full unit price in USD");
        assertEq(p, tokenPriceOneUnit / 2, "Principal should be set as half of one full unit price in USD");
        assertEq(i, 0, "No interest should have been accrued");
    }

    function test_can_repay_one_credit_and_keep_another() public {
        int prc = oracle.getLatestAnswer(address(supportedToken2));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        loan.depositAndRepay(1 ether);
        
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        bytes32 id2 = loan.ids(1);
        loan.borrow(id2, 1 ether);
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertEq(p + i, tokenPriceOneUnit, "Loan outstanding credit should be set as one full unit price in USD");
        assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
        assertEq(i, 0, "No interest should have been accrued");
    }


    function setupQueueTest(uint amount) internal returns (address[] memory) {
      address[] memory tokens = new address[](amount);
      // generate token for simulating different repayment flows
      for(uint i = 0; i < amount; i++) {
        RevenueToken token = new RevenueToken();
        tokens[i] = address(token);

        token.mint(address(this), mintAmount);
        token.approve(address(loan), mintAmount);
        token.approve(address(escrow), mintAmount);
        oracle.changePrice(address(token), 1 ether);
        escrow.enableCollateral(address(token));

        // add collateral for each token so we can borrow it during tests
        escrow.addCollateral(1 ether, address(token));
      }
      
      return tokens;
    }

    function test_positions_move_in_queue_of_2() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);

        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        bytes32 id2 = loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);

        assertEq(loan.ids(0), id);
        assertEq(loan.ids(1), id2);

        loan.borrow(id2, 1 ether);
        
        assertEq(loan.ids(0), id2);
        assertEq(loan.ids(1), id);

        loan.depositAndClose();

        assertEq(loan.ids(0), id);
    }

    function test_positions_move_in_queue_of_4_random_active_line() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);

        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        bytes32 id2 = loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);

        // create 3rd token to fully test array sorting
        address[] memory tokens = setupQueueTest(2);
        address token3 = tokens[0];
        address token4 = tokens[1];

        loan.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        bytes32 id3 = loan.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);
        bytes32 id4 = loan.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);

        assertEq(loan.ids(0), id);
        assertEq(loan.ids(1), id2);
        assertEq(loan.ids(2), id3);
        assertEq(loan.ids(3), id4);

        loan.borrow(id2, 1 ether);
        
        assertEq(loan.ids(0), id2);
        assertEq(loan.ids(1), id);
        assertEq(loan.ids(2), id3);
        assertEq(loan.ids(3), id4);
        
        loan.borrow(id4, 1 ether);

        assertEq(loan.ids(0), id2);
        assertEq(loan.ids(1), id4);
        assertEq(loan.ids(2), id3);
        assertEq(loan.ids(3), id); // id switches with id4, not just pushed one step back in queue

        loan.depositAndClose();

        assertEq(loan.ids(0), id4);
        assertEq(loan.ids(1), id3);
        assertEq(loan.ids(2), id);
    }



    // check that only borrowing from the last possible id will still sort queue properly
    // testing for bug in code where _i is initialized at 0 and never gets updated causing position to go to first position in repayment queue
    function test_positions_move_in_queue_of_4_only_last() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);

        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);
        bytes32 id2 = loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken2), lender);

        address[] memory tokens = setupQueueTest(2);
        address token3 = tokens[0];
        address token4 = tokens[1];

        loan.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        bytes32 id3 = loan.addCredit(drawnRate, facilityRate, 1 ether, address(token3), lender);
        
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);
        bytes32 id4 = loan.addCredit(drawnRate, facilityRate, 1 ether, address(token4), lender);

        assertEq(loan.ids(0), id);
        assertEq(loan.ids(1), id2);
        assertEq(loan.ids(2), id3);
        assertEq(loan.ids(3), id4);

        loan.borrow(id4, 1 ether);
        
        assertEq(loan.ids(0), id4);
        assertEq(loan.ids(1), id2);
        assertEq(loan.ids(2), id3);
        assertEq(loan.ids(3), id);
        
        loan.borrow(id, 1 ether);

        assertEq(loan.ids(0), id4);
        assertEq(loan.ids(1), id);
        assertEq(loan.ids(2), id3);
        assertEq(loan.ids(3), id2); // id switches with id4, not just pushed one step back in queue

        loan.depositAndRepay(1 wei);

        assertEq(loan.ids(0), id4);
        assertEq(loan.ids(1), id);
        assertEq(loan.ids(2), id3);
        assertEq(loan.ids(3), id2);

        loan.depositAndClose();

        assertEq(loan.ids(0), id);
        assertEq(loan.ids(1), id3);
        assertEq(loan.ids(2), id2);
    }

    function test_can_deposit_and_close_position() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        assertEq(supportedToken1.balanceOf(address(loan)), 1 ether, "Loan balance should be 1e18");
        loan.borrow(id, 1 ether);
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan balance should be 0");
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial mint balance");
        loan.depositAndClose();
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Tokens should be sent back to lender");
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertEq(p + i, 0, "Loan outstanding credit should be 0");
    }

    function test_can_withdraw_from_position() public {
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial mint balance");
        loan.addCredit(drawnRate, facilityRate, 0.5 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 0.5 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 0.5 ether, "Contract should have initial mint balance - 1e18 / 2");
        assertEq(supportedToken1.balanceOf(address(loan)), 0.5 ether, "Loan balance should be 1e18 / 2");
        loan.withdraw(id, 0.1 ether);
        assertEq(supportedToken1.balanceOf(address(loan)), 0.4 ether, "Loan balance should be 1e18 * 0.4");
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 0.4 ether, "Contract should have initial mint balance - 1e18 * 0.4");
    }

    function test_return_lender_funds_on_deposit_and_close() public {
      assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan balance should be 0");
      assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial mint balance");
      
      loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
      loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);

      bytes32 id = loan.ids(0);
      
      assert(id != bytes32(0));

      assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 1 ether, "Contract should have initial balance less lent amount");

      // test depsoitAndClose()
      loan.borrow(id, 1 ether);
      assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial balance after depositAndClose");
      loan.depositAndClose();
      assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial balance after depositAndClose");
      assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan should not have tokens");
      
      assertEq(uint(loan.loanStatus()), uint(LoanLib.STATUS.REPAID), "Loan not repaid");
    }

    function test_return_lender_funds_on_close() public {
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan balance should be 0");
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial mint balance");
        
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);

        bytes32 id = loan.ids(0);
        assert(id != bytes32(0));

        assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 1 ether, "Contract should have initial balance less lent amount");

        loan.borrow(id, 1 ether);
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial balance after depositAndClose");
        loan.depositAndRepay(1 ether);
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 1 ether, "Contract should have initial balance after depositAndClose");
        loan.close(id);

        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial balance after close");
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan should not have tokens");
        assertEq(uint(loan.loanStatus()), uint(LoanLib.STATUS.REPAID), "Loan not repaid");
    }

    function test_accrues_and_repays_facility_fee_on_close() public {
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan balance should be 0");
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial mint balance");
        
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);

        bytes32 id = loan.ids(0);

        assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 1 ether, "Contract should have initial balance less lent amount");

        loan.borrow(id, 1 ether);
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial balance after depositAndClose");
        loan.depositAndRepay(1 ether);
        assertEq(supportedToken1.balanceOf(address(this)), mintAmount - 1 ether, "Contract should have initial balance after depositAndClose");

        loan.close(id);

        assertEq(supportedToken1.balanceOf(address(this)), mintAmount, "Contract should have initial balance after close");
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan should not have tokens");
        assertEq(uint(loan.loanStatus()), uint(LoanLib.STATUS.REPAID), "Loan not repaid");
    }

    function test_loan_status_changes_to_liquidatable() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        oracle.changePrice(address(supportedToken2), 1);
        assert(loan.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
    }

    function test_cannot_open_credit_position_if_only_one_party_agrees() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        assertEq(supportedToken1.balanceOf(address(loan)), 0, "Loan balance should be 0");
    }

    function testFail_cannot_open_credit_position_if_only_one_party_agrees() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.ids(0);
    }

    function testFail_cannot_borrow_from_credit_position_if_under_collateralised() public {
        loan.addCredit(drawnRate, facilityRate, 100 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 100 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 100 ether);
    }

    function testFail_cannot_withdraw_if_all_loaned_out() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        loan.withdraw(id, 0.1 ether);
    }

    function testFail_cannot_borrow_more_than_position() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 100 ether);
    }

    function testFail_cannot_create_credit_with_tokens_unsupported_by_oracle() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(unsupportedToken), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(unsupportedToken), lender);
    }

    function testFail_cannot_borrow_if_not_active() public {
        assert(loan.healthcheck() == LoanLib.STATUS.ACTIVE);
        loan.addCredit(drawnRate, facilityRate, 0.1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 0.1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 0.1 ether);
        oracle.changePrice(address(supportedToken2), 1);
        assert(loan.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
        loan.borrow(id, 0.9 ether);
    }

    function testFail_cannot_borrow_against_closed_position() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        loan.depositAndClose();
        loan.borrow(id, 1 ether);
    }

    function testFail_cannot_manually_close_if_credit_outstanding() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 0.1 ether);
        loan.close(id);
    }

    function testFail_cannot_liquidate_escrow_if_cratio_above_min() public {
        loan.liquidate(0, 1 ether, address(supportedToken1));
    }

    function testFail_health_is_not_liquidatable_if_cratio_above_min() public {
        assert(loan.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
    }

    function test_increase_credit_limit_with_consent() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        (uint d,,,,,,) = loan.credits(id);
        

        loan.increaseCredit(id, 1 ether);
        loan.increaseCredit(id, 1 ether);
        (uint d2,,,,,,) = loan.credits(id);
        assertEq(d2 - d, 1 ether);
    }

    // function test_cannot_increase_credit_limit_without_consent() public {
    //     // TODO need a way to fake `lender` so mutualConsentById will fail
    //     loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     bytes32 id = loan.ids(0);
    //     (uint d,,,,,,) = loan.credits(id);
        

    //     // try to mock lender address as someone else
    //     loan.increaseCredit(id, 1 ether);
    //     loan.increaseCredit(id, 1 ether);
    //     (uint d2,,,,,,) = loan.credits(id); 
    //     assertEq(d2, d);
    // }

    function test_can_update_rates_with_consent() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
      

        loan.setRates(id, uint128(1 ether), uint128(1 ether));
        loan.setRates(id, uint128(1 ether), uint128(1 ether));
        (uint128 drate, uint128 frate,) = loan.interestRate().rates(id);
        assertEq(drate, uint128(1 ether));
        assertEq(frate, uint128(1 ether));
        assertGt(frate, facilityRate);
        assertGt(drate, drawnRate);
    }

    // function test_cannot_update_rates_without_consent() public {
    //     // TODO need a way to fake `lender` so mutualConsentById will fail
    //     loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
    //     bytes32 id = loan.ids(0);
      

    //     // try to mock lender address as someone else
    //     loan.setRates(id, uint128(1 ether), uint128(1 ether));
    //     loan.setRates(id, uint128(1 ether), uint128(1 ether));
    //     (uint128 drate, uint128 frate,) = loan.interestRate().rates(id);
    //     assertEq(facilityRate, frate);
    //     assertEq(drawnRate, drate);
    // }


}
