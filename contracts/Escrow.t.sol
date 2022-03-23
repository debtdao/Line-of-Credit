pragma solidity 0.8.9;

import { DSTest } from  "../lib/ds-test/src/test.sol";
import { Escrow } from "./Escrow.sol";
import { LoanLib } from "./lib/LoanLib.sol";
import { RevenueToken } from "./mock/RevenueToken.sol";
import { SimpleOracle } from "./mock/SimpleOracle.sol";
import { MockLoan } from "./mock/MockLoan.sol";

contract EscrowTest is DSTest {

    Escrow escrow;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    SimpleOracle oracle;
    MockLoan loan;
    uint mintAmount = 100 ether;
    uint MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint minCollateralRatio = 1 ether; // 100%

    address borrower;
    address arbiter = address(1);

    function setUp() public {
        borrower = address(this);
        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();
        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));
        loan = new MockLoan(1);
        _createEscrow(minCollateralRatio, address(oracle), address(loan), borrower);
        loan.setEscrow(address(escrow));
        _mintAndApprove();
    }

    function _mintAndApprove() internal {
        supportedToken1.mint(borrower, mintAmount);
        supportedToken1.approve(address(escrow), MAX_INT);
        supportedToken2.mint(borrower, mintAmount);
        supportedToken2.approve(address(escrow), MAX_INT);
        unsupportedToken.mint(borrower, mintAmount);
        unsupportedToken.approve(address(escrow), MAX_INT);
    }

    function _createEscrow(
        uint _minimumCollateralRatio,
        address _oracle,
        address _loan,
        address _borrower
    ) internal returns(address) {
        escrow = new Escrow(_minimumCollateralRatio, _oracle, _loan, _borrower);

        return address(escrow);
    }

    function test_can_get_correct_collateral_value() public {
        escrow.addCollateral(mintAmount, address(supportedToken1));
        uint collateralValue = escrow.getCollateralValue();
        assert(collateralValue == (1000 * 1e8) * (mintAmount / 1 ether));
    }

    function test_can_add_collateral() public {
        uint borrowerBalance = supportedToken1.balanceOf(borrower);
        escrow.addCollateral(mintAmount, address(supportedToken1));
        assert(borrowerBalance == supportedToken1.balanceOf(borrower) + mintAmount);
        uint borrowerBalance2 = supportedToken2.balanceOf(borrower);
        escrow.addCollateral(mintAmount, address(supportedToken2));
        assert(borrowerBalance2 == supportedToken2.balanceOf(borrower) + mintAmount);
    }

    function test_can_remove_collateral() public {
        escrow.addCollateral(mintAmount, address(supportedToken1));
        uint borrowerBalance = supportedToken1.balanceOf(borrower);
        escrow.releaseCollateral(1 ether, address(supportedToken1), borrower);
        assert(borrowerBalance + 1 ether == supportedToken1.balanceOf(borrower));
    }

    function test_cratio_adjusts_when_collateral_changes() public {
        loan.setDebtValue(1 ether);
        escrow.addCollateral(1 ether, address(supportedToken1));
        uint escrowRatio = escrow.getCollateralRatio();
        escrow.addCollateral(1 ether, address(supportedToken1));
        assert(escrow.getCollateralRatio() == escrowRatio * 2);
        escrow.addCollateral(1 ether, address(supportedToken2));
        assert(escrow.getCollateralRatio() == escrowRatio * 4);
    }

    function test_cratio_adjusts_when_collateral_price_changes() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.setDebtValue(1000);
        uint escrowRatio = escrow.getCollateralRatio();
        oracle.changePrice(address(supportedToken1), 10000 * 1e8);
        uint newEscrowRatio = escrow.getCollateralRatio();
        assert(newEscrowRatio == escrowRatio * 10);
    }

    function test_can_liquidate() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        escrow.addCollateral(0.9 ether, address(supportedToken2));
        loan.setDebtValue(2000 ether);
        assert(minCollateralRatio > escrow.getCollateralRatio());
        loan.liquidate(0, 1 ether, address(supportedToken1), arbiter);
        loan.liquidate(0, 0.9 ether, address(supportedToken2), arbiter);
        assert(supportedToken1.balanceOf(arbiter) == 1 ether);
        assert(supportedToken2.balanceOf(arbiter) == 0.9 ether);
    }

    function test_cratio_should_be_max_int_if_no_debt() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.setDebtValue(0);
        assert(escrow.getCollateralRatio() == MAX_INT);
    }

    function test_cratio_values() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.setDebtValue(1000 * 1e8); // 1e18 of supportedToken1 == 1000 * 1e8 (1000 USD)
        assert(escrow.getCollateralRatio() == 1 ether); // cratio is at 100%
        loan.setDebtValue(10 * (1000 * 1e8)); // 10x the collateral value (10000 USD)
        assert(escrow.getCollateralRatio() == 0.1 ether); // 10%
        escrow.addCollateral(1 ether, address(supportedToken2)); // worth 2000 * 1e8 (2000 USD)
        assert(escrow.getCollateralRatio() == 0.3 ether); // 30%
        escrow.addCollateral(10 ether, address(supportedToken2));
        assert(escrow.getCollateralRatio() == 2.3 ether); // 230%
    }

    function test_cratio_should_be_0_if_no_collateral() public {
        loan.setDebtValue(1000);
        assert(escrow.getCollateralRatio() == 0);
    }

    function testFail_cannot_remove_collateral_when_under_collateralized() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.setDebtValue(2000 ether);
        escrow.releaseCollateral(1 ether, address(supportedToken1), borrower);
    }

    function testFail_cannot_liquidate_when_loan_healthy() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.liquidate(0, 1 ether, address(supportedToken1), arbiter);
    }

    function testFail_cannot_add_collateral_if_unsupported_by_oracle() public {
        escrow.addCollateral(1000, address(unsupportedToken));
    }
}