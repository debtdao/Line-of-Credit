pragma solidity 0.8.9;

import { Escrow } from "./Escrow.sol";
import { DSTest } from  "../../../lib/ds-test/src/test.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { RevenueToken } from "../../mock/RevenueToken.sol";
import { RevenueToken4626 } from "../../mock/RevenueToken4626.sol";
import { SimpleOracle } from "../../mock/SimpleOracle.sol";
import { MockLoan } from "../../mock/MockLoan.sol";

contract EscrowTest is DSTest {

    Escrow escrow;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    RevenueToken4626 token4626;
    SimpleOracle oracle;
    MockLoan loan;
    uint mintAmount = 100 ether;
    uint MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint minCollateralRatio = 1 ether; // 100%

    address borrower;
    address arbiter = address(1);

    function setUp() public {
        borrower = address(this);
        // deploy tokens and add oracle prices for valid collateral
        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();
        token4626 = new RevenueToken4626(address(supportedToken1));
        oracle = new SimpleOracle(address(supportedToken1), address(supportedToken2));
        loan = new MockLoan(1);
        // deploy and save escrow
        _createEscrow(minCollateralRatio, address(oracle), address(loan), borrower);
        // add escrow to mock loan
        loan.setEscrow(address(escrow));
        // allow tokens to be deposited as collateral
        escrow.enableCollateral(address(supportedToken1));
        escrow.enableCollateral(address(supportedToken2));
        _mintAndApprove();
    }

    function _mintAndApprove() internal {
        supportedToken1.mint(borrower, mintAmount);
        supportedToken1.approve(address(escrow), MAX_INT);
        supportedToken2.mint(borrower, mintAmount);
        supportedToken2.approve(address(escrow), MAX_INT);
        unsupportedToken.mint(borrower, mintAmount);
        unsupportedToken.approve(address(escrow), MAX_INT);
        token4626.mint(borrower, mintAmount);
        token4626.approve(address(escrow), MAX_INT);
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
        assertEq(collateralValue, (1000 * 1e8) * (mintAmount / 1 ether), "collateral value should equal the mint amount * price");
    }

    function test_can_get_correct_collateral_value_eip4626() public {
        token4626.setAssetAddress(address(supportedToken1));
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(mintAmount, address(token4626));
        uint collateralValue = escrow.getCollateralValue();
        assertEq(collateralValue, (1000 * 1e8) * (mintAmount / 1 ether), "collateral value should equal the mint amount * price");
    }

    function test_can_add_collateral() public {
        uint borrowerBalance = supportedToken1.balanceOf(borrower);
        escrow.addCollateral(mintAmount, address(supportedToken1));
        assertEq(borrowerBalance, supportedToken1.balanceOf(borrower) + mintAmount, "borrower should have decreased with collateral deposit");
        uint borrowerBalance2 = supportedToken2.balanceOf(borrower);
        escrow.addCollateral(mintAmount, address(supportedToken2));
        assertEq(borrowerBalance2, supportedToken2.balanceOf(borrower) + mintAmount, "borrower should have decreased with collateral deposit");
    }

    function test_can_add_collateral_eip4626() public {
        uint borrowerBalance = token4626.balanceOf(borrower);
        token4626.setAssetAddress(address(supportedToken2));
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(mintAmount, address(token4626));
        assertEq(borrowerBalance, token4626.balanceOf(borrower) + mintAmount, "borrower balance should have been reduced by mintAmount");
    }

    function test_can_remove_collateral_eip4626() public {
        uint borrowerBalance = token4626.balanceOf(borrower);
        token4626.setAssetAddress(address(supportedToken2));
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(mintAmount, address(token4626));
        escrow.releaseCollateral(1 ether, address(token4626), borrower);
        assertEq(1 ether, token4626.balanceOf(borrower), "should have returned collateral");
    }

    function test_can_remove_collateral() public {
        escrow.addCollateral(mintAmount, address(supportedToken1));
        uint borrowerBalance = supportedToken1.balanceOf(borrower);
        escrow.releaseCollateral(1 ether, address(supportedToken1), borrower);
        assertEq(borrowerBalance + 1 ether, supportedToken1.balanceOf(borrower), "borrower should have released collateral");
    }

    function test_cratio_adjusts_when_collateral_changes() public {
        loan.setDebtValue(1 ether);
        escrow.addCollateral(1 ether, address(supportedToken1));
        uint escrowRatio = escrow.getCollateralRatio();
        escrow.addCollateral(1 ether, address(supportedToken1));
        assertEq(escrow.getCollateralRatio(), escrowRatio * 2, "cratio should be 2x the original");
        escrow.addCollateral(1 ether, address(supportedToken2));
        assertEq(escrow.getCollateralRatio(), escrowRatio * 4, "cratio should be 4x the original");
    }

    function test_cratio_adjusts_when_collateral_price_changes() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.setDebtValue(1000);
        uint escrowRatio = escrow.getCollateralRatio();
        oracle.changePrice(address(supportedToken1), 10000 * 1e8);
        uint newEscrowRatio = escrow.getCollateralRatio();
        assertEq(newEscrowRatio, escrowRatio * 10, "new cratio should be 10x the original");
    }

    function test_cratio_adjusts_when_collateral_price_changes_eip4626() public {
        token4626.setAssetAddress(address(supportedToken1));
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(1 ether, address(token4626));
        loan.setDebtValue(1000);
        uint escrowRatio = escrow.getCollateralRatio();
        oracle.changePrice(address(supportedToken1), 10000 * 1e8);
        uint newEscrowRatio = escrow.getCollateralRatio();
        assertEq(newEscrowRatio, escrowRatio * 10, "new cratio should be 10x the original");
    }

    function test_can_liquidate() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        escrow.addCollateral(0.9 ether, address(supportedToken2));
        loan.setDebtValue(2000 ether);
        assertGt(minCollateralRatio, escrow.getCollateralRatio(), "should be below the liquidation threshold");
        loan.liquidate(0, 1 ether, address(supportedToken1), arbiter);
        loan.liquidate(0, 0.9 ether, address(supportedToken2), arbiter);
        assertEq(supportedToken1.balanceOf(arbiter), 1 ether, "arbiter should have received token 1");
        assertEq(supportedToken2.balanceOf(arbiter), 0.9 ether, "arbiter should have received token 2");
    }

    function test_can_liquidate_eip4626() public {
        token4626.setAssetAddress(address(supportedToken1));
        token4626.setAssetMultiplier(5);
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(1 ether, address(token4626));
        loan.setDebtValue(2000 ether);
        assertGt(minCollateralRatio, escrow.getCollateralRatio(), "should be below the liquidation threshold");
        loan.liquidate(0, 1 ether, address(token4626), arbiter);
        assertEq(token4626.balanceOf(arbiter), 1 ether, "arbiter should have received 1e18 worth of the 4626 token");
    }

    function test_cratio_should_be_max_int_if_no_debt() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.setDebtValue(0);
        assertEq(escrow.getCollateralRatio(), MAX_INT, "cratio should be set to MAX");
    }

    function test_cratio_values() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.setDebtValue(1000 * 1e8); // 1e18 of supportedToken1 == 1000 * 1e8 (1000 USD)
        assertEq(escrow.getCollateralRatio(), 1 ether, "cratio should be at 100%"); // cratio is at 100%
        loan.setDebtValue(10 * (1000 * 1e8)); // 10x the collateral value (10000 USD)
        assertEq(escrow.getCollateralRatio(), 0.1 ether, "cratio should be at 10%"); // 10%
        escrow.addCollateral(1 ether, address(supportedToken2)); // worth 2000 * 1e8 (2000 USD)
        assertEq(escrow.getCollateralRatio(), 0.3 ether, "cratio should be at 30%"); // 30%
        escrow.addCollateral(10 ether, address(supportedToken2));
        assertEq(escrow.getCollateralRatio(), 2.3 ether, "cratio should be at 230%"); // 230%
    }

    function test_cratio_should_be_0_if_no_collateral() public {
        loan.setDebtValue(1000);
        assertEq(escrow.getCollateralRatio(), 0, "cratio should be 0");
    }

    function test_cratio_values_with_eip4626() public {
        token4626.setAssetAddress(address(supportedToken2));
        token4626.setAssetMultiplier(2); // share token should be worth double the underlying (which is now supportedToken2)
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(1 ether, address(token4626));
        loan.setDebtValue(4000 * 1e8); // 1e18 of supportedToken2 * 2 == 4000 * 1e8 (4000 USD)
        assertEq(escrow.getCollateralRatio(), 1 ether, "cratio should be 100%");
        loan.setDebtValue(10 * (4000 * 1e8)); // 10x the collateral value (40000 USD)
        assertEq(escrow.getCollateralRatio(), 0.1 ether, "cratio should be 10%");
        escrow.addCollateral(1 ether, address(supportedToken2)); // worth 2000 * 1e8 (2000 USD)
        assertEq(escrow.getCollateralRatio(), 0.15 ether, "cratio should be 15%");
        escrow.addCollateral(10 ether, address(supportedToken2));
        assertEq(escrow.getCollateralRatio(), 0.65 ether, "cratio should be 65%");
    }

    function testFail_cannot_remove_collateral_when_under_collateralized() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.setDebtValue(2000 ether);
        escrow.releaseCollateral(1 ether, address(supportedToken1), borrower);
    }

    function testFail_cannot_remove_collateral_when_under_collateralized_eip4626() public {
        token4626.setAssetAddress(address(supportedToken1));
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(1 ether, address(token4626));
        loan.setDebtValue(2000 ether);
        escrow.releaseCollateral(1 ether, address(token4626), borrower);
    }

    function testFail_cannot_liquidate_when_loan_healthy() public {
        escrow.addCollateral(1 ether, address(supportedToken1));
        loan.liquidate(0, 1 ether, address(supportedToken1), arbiter);
    }

    function testFail_cannot_liquidate_when_loan_healthy_eip4626() public {
        token4626.setAssetAddress(address(supportedToken1));
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(1 ether, address(token4626));
        loan.liquidate(0, 1 ether, address(token4626), arbiter);
    }

    function testFail_cannot_add_collateral_if_unsupported_by_oracle() public {
        escrow.addCollateral(1000, address(unsupportedToken));
    }

    function testFail_cannot_add_collateral_if_unsupported_by_oracle_eip4626() public {
        token4626.setAssetAddress(address(unsupportedToken));
        escrow.enableCollateral(address(token4626));
        escrow.addCollateral(1000, address(token4626));
    }
}
