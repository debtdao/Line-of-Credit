pragma solidity 0.8.9;

import { DSTest } from  "../lib/ds-test/src/test.sol";
import { Escrow } from "./Escrow.sol";
import { LoanLib } from "./lib/LoanLib.sol";
import { RevenueToken } from "./mock/RevenueToken.sol";
import { SimpleOracle } from "./mock/SimpleOracle.sol";
import { Loan } from "./Loan.sol";

contract EscrowTest is DSTest {

    Escrow escrow;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    SimpleOracle oracle;
    Loan loan;
    uint mintAmount = 100 ether;
    uint approveAmount = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint minCollateral = 1 ether; // 100%
    uint maxDebtUSD = 100 * 1e8; // 100 USD

    address borrower;
    address lender = address(1);
    address arbiter = address(2);

    function setUp() public {
        borrower = address(this);
        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();
        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));
        _createEscrow(minCollateral, address(oracle), lender, borrower, arbiter);
        loan = new Loan(maxDebtUSD, address(oracle), address(0), arbiter, borrower, address(escrow), address(0));
        _mintAndApprove();
    }

    function _mintAndApprove() internal {
        supportedToken1.mint(borrower, mintAmount);
        supportedToken1.approve(address(escrow), approveAmount);
        supportedToken2.mint(borrower, mintAmount);
        supportedToken2.approve(address(escrow), approveAmount);
        unsupportedToken.mint(borrower, mintAmount);
        unsupportedToken.approve(address(escrow), approveAmount);
    }

    function _createEscrow(
        uint _minimumCollateralRatio,
        address _oracle,
        address _lender,
        address _borrower,
        address _arbiter
    ) internal returns(address) {
        escrow = new Escrow(_minimumCollateralRatio, _oracle, _lender, _borrower, _arbiter);

        return address(escrow);
    }

    function activate() internal {
        address[] memory tokensToDeposit = new address[](1);
        uint[] memory amounts = new uint[](1);
        tokensToDeposit[0] = address(supportedToken1);
        amounts[0] = 1 ether;
        escrow.activate(tokensToDeposit, amounts);
    }

    function test_health_check_is_uninitialized() public {
        assert(escrow.healthcheck() == LoanLib.STATUS.UNINITIALIZED);
    }

    function test_can_update_health_check_from_uninitialized_to_initialized() public {
        assert(escrow.healthcheck() == LoanLib.STATUS.UNINITIALIZED);
        escrow.init();
        assert(escrow.healthcheck() == LoanLib.STATUS.INITIALIZED);
    }

    function test_can_activate() public {
        escrow.init();
        activate();
        assert(escrow.lastUpdatedStatus() == LoanLib.STATUS.ACTIVE);
    }

    function test_can_add_collateral() public {
        escrow.init();
        activate();
        _mintAndApprove();
        uint borrowerBalance = supportedToken1.balanceOf(borrower);
        escrow.addCollateral(mintAmount, address(supportedToken1));
        assert(borrowerBalance == supportedToken1.balanceOf(borrower) - mintAmount);
    }

    function test_can_remove_collateral() public {
        escrow.init();
        activate();
        escrow.addCollateral(mintAmount, address(supportedToken1));
        uint userBalance = supportedToken1.balanceOf(msg.sender);
        escrow.releaseCollateral(mintAmount, address(supportedToken1), msg.sender);
        assert(userBalance == supportedToken1.balanceOf(msg.sender) + mintAmount);
    }

    function test_cratio_adjusts_when_collateral_changes() public {
        loan.init();
        activate();
        loan.addDebtPosition(1 ether, address(supportedToken1), address(0));
        uint escrowRatio = escrow.getCollateralRatio();
        escrow.addCollateral(1 ether, address(supportedToken1));
        uint newEscrowRatio = escrow.getCollateralRatio();
        assert(newEscrowRatio > escrowRatio);
    }

    function test_cratio_adjusts_when_collateral_price_changes() public {
        loan.init();
        activate();
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.addDebtPosition(1 ether, address(supportedToken1), address(0));
        uint escrowRatio = escrow.getCollateralRatio();
        oracle.changePrice(address(supportedToken1), 10000);
        uint newEscrowRatio = escrow.getCollateralRatio();
        // TODO assert how much the ratio should have changed rather than just >
        assert(newEscrowRatio > escrowRatio);
    }

    function test_can_liquidate() public {
        loan.init();
        activate();
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.addDebtPosition(1 ether, address(supportedToken2), address(0));
        oracle.changePrice(address(supportedToken1), 0);
        assert(escrow.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
        escrow.liquidate(address(supportedToken1), 1 ether);
        assert(supportedToken1.balanceOf(address(2)) == 1000);
    }

    function testFail_cannot_activate_if_uninitialized() public {
        activate();
    }

    function testFail_cannot_remove_collateral_when_under_collateralized() public {
        loan.init();
        activate();
        loan.addDebtPosition(100, address(supportedToken1), address(0));
        escrow.releaseCollateral(1, address(supportedToken1), msg.sender);
    }

    function testFail_cannot_liquidate_when_loan_healthy() public {
        escrow.init();
        activate();
        escrow.liquidate(address(supportedToken1), 1000);
    }

    function testFail_cannot_add_collateral_if_unsupported_by_oracle() public {
        escrow.init();
        activate();
        escrow.addCollateral(1000, address(unsupportedToken));
    }
}