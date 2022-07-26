pragma solidity 0.8.9;

import { Escrow } from "../escrow/Escrow.sol";
import { Spigot } from "../spigot/Spigot.sol";
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
        
        escrow = new Escrow(minCollateralRatio, address(oracle),address(this), borrower);
        Spigot spigot = new Spigot(address(this), borrower, borrower);

        loan = new SecuredLoan(
          address(oracle),
          arbiter,
          borrower,
          address(0),
          address(spigot),
          address(escrow),
          1 ether,
          150 days,
          0
        );
        
        escrow.updateLoan(address(loan));
        spigot.updateOwner(address(loan));
        loan.init();

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
        (uint p ,) = loan.updateOutstandingDebt();
        assert(p > 0);
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
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
    }

    function test_can_manually_close_if_no_outstanding_credit() public {
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        loan.depositAndRepay(1 ether);
        assertEq(loan.getOutstandingDebt(), 0, "Loan outstanding credit should be 0");
        loan.close(id);
    }

    function test_can_repay_loan() public {
        int prc = oracle.getLatestAnswer(address(supportedToken1));
        uint tokenPriceOneUnit = prc < 0 ? 0 : uint(prc);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        loan.addCredit(drawnRate, facilityRate, 1 ether, address(supportedToken1), lender);
        bytes32 id = loan.ids(0);
        loan.borrow(id, 1 ether);
        assertEq(loan.getOutstandingDebt(), tokenPriceOneUnit, "Loan outstanding credit should be set as one full unit price in USD");
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
        assertEq(i, 0, "No interest should have been accrued");
        loan.depositAndRepay(1 ether);
        assertEq(loan.getOutstandingDebt(), 0, "Loan outstanding credit should be 0");
        (uint p2, uint i2) = loan.updateOutstandingDebt();
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
        assertEq(loan.getOutstandingDebt(), tokenPriceOneUnit / 2, "Loan outstanding credit should be set as half of one full unit price in USD");
        (uint p2, uint i2) = loan.updateOutstandingDebt();
        assertEq(p2, tokenPriceOneUnit / 2, "Principal should be set as half of one full unit price in USD");
        assertEq(i2, 0, "No interest should have been accrued");
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
        assertEq(loan.getOutstandingDebt(), tokenPriceOneUnit, "Loan outstanding credit should be set as one full unit price in USD");
        (uint p, uint i) = loan.updateOutstandingDebt();
        assertEq(p, tokenPriceOneUnit, "Principal should be set as one full unit price in USD");
        assertEq(i, 0, "No interest should have been accrued");
    }

    function testFail_can_repay_loan_later_in_queue() public {
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

        loan.depositAndRepay(1 ether); // this should fail
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
        assertEq(loan.getOutstandingDebt(), 0, "Loan outstanding credit should be 0");
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

}
