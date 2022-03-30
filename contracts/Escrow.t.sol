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

    function setUp() public {
        supportedToken1 = new RevenueToken();
        supportedToken1.mint(msg.sender, 1000000000);
        supportedToken1.approve(address(this), 1000000000);
        supportedToken2 = new RevenueToken();
        supportedToken2.mint(msg.sender, 1000000000);
        supportedToken2.approve(address(this), 1000000000);
        unsupportedToken = new RevenueToken();
        unsupportedToken.mint(msg.sender, 1000000000);
        unsupportedToken.approve(address(this), 1000000000);
        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));
        address escrow = _initEscrow(10, address(oracle), address(1), msg.sender, address(2));
        loan = new Loan(100, address(oracle), address(0), address(0), msg.sender, escrow, address(0));
    }

    function _initEscrow(
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
        amounts[0] = 100;
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

    function test_can_add_collateral() public {
        escrow.init();
        activate();
        uint userBalance = supportedToken1.balanceOf(msg.sender);
        escrow.addCollateral(1000, address(supportedToken1));
        assert(userBalance == supportedToken1.balanceOf(msg.sender) - 1000);
    }

    function test_can_remove_collateral() public {
        escrow.init();
        activate();
        escrow.addCollateral(1000, address(supportedToken1));
        uint userBalance = supportedToken1.balanceOf(msg.sender);
        escrow.releaseCollateral(100, address(supportedToken1), msg.sender);
        assert(userBalance == supportedToken1.balanceOf(msg.sender) + 100);
    }

    function test_cratio_adjusts_when_collateral_changes() public {
        loan.init();
        activate();
        loan.addDebtPosition(100, address(supportedToken1), address(0));
        uint escrowRatio = escrow.getCollateralRatio();
        escrow.addCollateral(1000, address(supportedToken1));
        uint newEscrowRatio = escrow.getCollateralRatio();
        assert(newEscrowRatio > escrowRatio);
    }

    function test_cratio_adjusts_when_collateral_price_changes() public {
        loan.init();
        activate();
        escrow.addCollateral(1000, address(supportedToken1));
        loan.addDebtPosition(100, address(supportedToken1), address(0));
        uint escrowRatio = escrow.getCollateralRatio();
        oracle.changePrice(address(supportedToken1), 10000);
        uint newEscrowRatio = escrow.getCollateralRatio();
        // TODO assert how much the ratio should have changed rather than just >
        assert(newEscrowRatio > escrowRatio);
    }

    function test_can_liquidate() public {
        loan.init();
        activate();
        escrow.addCollateral(1000, address(supportedToken1));
        loan.addDebtPosition(100, address(supportedToken2), address(0));
        oracle.changePrice(address(supportedToken1), 0);
        assert(escrow.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
        escrow.liquidate(address(supportedToken1), 1000);
        assert(supportedToken1.balanceOf(address(2)) == 1000);
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