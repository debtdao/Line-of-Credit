pragma solidity 0.8.9;

import { DSTest } from  "../lib/ds-test/src/test.sol";
import { Escrow } from "./Escrow.sol";
import { LoanLib } from "./lib/LoanLib.sol";
import { RevenueToken } from "./mock/RevenueToken.sol";
import { SimpleOracle } from "./mock/SimpleOracle.sol";

contract EscrowTest is DSTest {

    Escrow escrow;
    RevenueToken revenueToken;
    RevenueToken unsupportedToken;
    SimpleOracle oracle;

    function setUp() public {
        revenueToken = new RevenueToken();
        revenueToken.mint(msg.sender, 1000000000);
        revenueToken.approve(address(this), 1000000000);
        unsupportedToken = new RevenueToken();
        unsupportedToken.mint(msg.sender, 1000000000);
        unsupportedToken.approve(address(this), 1000000000);
        oracle = new SimpleOracle(address(revenueToken));
        _initEscrow(10, msg.sender, address(oracle), address(1), msg.sender, address(2));
    }

    function _initEscrow(
        uint _minimumCollateralRatio,
        address _loanContract,
        address _oracle,
        address _lender,
        address _borrower,
        address _arbiter
    ) internal {
        escrow = new Escrow(_minimumCollateralRatio, _loanContract, _oracle, _lender, _borrower, _arbiter);
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
        uint userBalance = revenueToken.balanceOf(msg.sender);
        escrow.addCollateral(1000, address(revenueToken));
        assert(userBalance == revenueToken.balanceOf(msg.sender) - 1000);
    }

    function test_can_remove_collateral() public {
        escrow.addCollateral(1000, address(revenueToken));
        uint userBalance = revenueToken.balanceOf(msg.sender);
        escrow.releaseCollateral(100, address(revenueToken), msg.sender);
        assert(userBalance == revenueToken.balanceOf(msg.sender) + 100);
    }

    function test_cratio_adjusts_when_collateral_changes() public {
        uint escrowRatio = escrow.getCollateralRatio();
        escrow.addCollateral(1000, address(revenueToken));
        uint newEscrowRatio = escrow.getCollateralRatio();
        assert(newEscrowRatio > escrowRatio);
    }

    function test_cratio_adjusts_when_collateral_price_changes() public {
        escrow.addCollateral(1000, address(revenueToken));
        uint escrowRatio = escrow.getCollateralRatio();
        oracle.changePrice(10000);
        uint newEscrowRatio = escrow.getCollateralRatio();
        // TODO assert how much the ratio should have changed rather than just >
        assert(newEscrowRatio > escrowRatio);
    }

    function test_can_liquidate() public {
        // todo need to make loan
        escrow.addCollateral(1000, address(revenueToken));
        oracle.changePrice(0);
        assert(escrow.healthcheck() == LoanLib.STATUS.LIQUIDATABLE);
        escrow.liquidate(address(revenueToken), 1000);
        assert(revenueToken.balanceOf(address(2)) == 1000);
    }

    function testFail_cannot_remove_collateral_when_under_collateralized() public {
        // todo need to make loan
        escrow.addCollateral(1000, address(revenueToken));
        escrow.releaseCollateral(100, address(revenueToken), msg.sender);
    }

    function testFail_cannot_liquidate_when_loan_healthy() public {
        escrow.addCollateral(1000, address(revenueToken));
        escrow.liquidate(address(revenueToken), 1000);
    }

    function testFail_cannot_add_collateral_if_unsupported_by_oracle() public {
        escrow.addCollateral(1000, address(unsupportedToken));
    }
}