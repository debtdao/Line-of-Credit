pragma solidity 0.8.9;

import { Escrow } from "../escrow/Escrow.sol";
import { DSTest } from  "../../../lib/ds-test/src/test.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { RevenueToken } from "../../mock/RevenueToken.sol";
import { SimpleOracle } from "../../mock/SimpleOracle.sol";
import { BasicEscrowedLoan } from "./BasicEscrowedLoan.sol";

contract LoanTest is DSTest {

    Escrow escrow;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    SimpleOracle oracle;
    BasicEscrowedLoan loan;
    uint mintAmount = 100 ether;
    uint MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint minCollateralRatio = 1 ether; // 100%

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
        loan = new BasicEscrowedLoan(1 ether, address(oracle), arbiter, borrower, address(0), 1 ether);
        escrow = loan.escrow();
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
        loan.addDebtPosition(1 ether, address(supportedToken1), lender);
        loan.addDebtPosition(1 ether, address(supportedToken1), lender);
        uint balanceOfEscrow = supportedToken2.balanceOf(address(escrow));
        uint balanceOfArbiter = supportedToken2.balanceOf(arbiter);
        bytes32 positionId = loan.positionIds(0);
        loan.borrow(positionId, 1 ether);
        assert(loan.principal() > 0);
        oracle.changePrice(address(supportedToken2), 1);
        loan.liquidate(positionId, 1 ether, address(supportedToken2));
        assert(balanceOfEscrow == supportedToken2.balanceOf(address(escrow)) + 1 ether);
        assert(balanceOfArbiter + 1 ether == supportedToken2.balanceOf(arbiter));
    }

    function test_health_becomes_liquidatable_if_cratio_below_min() public {
        assert(loan.healthcheck() == LoanLib.STATUS.ACTIVE);
        loan.addDebtPosition(1 ether, address(supportedToken1), lender);
        loan.addDebtPosition(1 ether, address(supportedToken1), lender);
        bytes32 positionId = loan.positionIds(0);
        loan.borrow(positionId, 1 ether);
        oracle.changePrice(address(supportedToken2), 1);
        assert(loan.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
    }

    function testFail_cannot_liquidate_escrow_if_cratio_above_min() public {
        loan.liquidate(0, 1 ether, address(supportedToken1));
    }

    function testFail_health_is_not_liquidatable_if_cratio_above_min() public {
        assert(loan.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
    }

}
