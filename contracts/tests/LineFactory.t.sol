pragma solidity 0.8.9;

import "forge-std/Test.sol";

import {RevenueToken} from "../mock/RevenueToken.sol";
import {LineFactory} from "../modules/factories/LineFactory.sol";
import {ModuleFactory} from "../modules/factories/ModuleFactory.sol";
import {ILineFactory} from "../interfaces/ILineFactory.sol";
import {ISecuredLine} from "../interfaces/ISecuredLine.sol";
import {ISpigot} from "../interfaces/ISpigot.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {Spigot} from "../modules/spigot/Spigot.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";
import {LineLib} from "../utils/LineLib.sol";

contract LineFactoryTest is Test {
    SecuredLine line;
    Spigot spigot;
    Escrow escrow;
    LineFactory lineFactory;
    ModuleFactory moduleFactory;

    address oracle;
    address arbiter;
    address borrower;
    address swapTarget;
    uint256 ttl = 90 days;
    address line_address;
    address spigot_address;
    address escrow_address;

    function setUp() public {
        oracle = address(0xdebf);
        arbiter = address(0xf1c0);
        borrower = address(0xbA05);
        swapTarget = address(0xb0b0);

        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(
            address(moduleFactory),
            arbiter,
            oracle,
            swapTarget
        );

        line_address = lineFactory.deploySecuredLine(borrower, ttl);

        line = SecuredLine(payable(line_address));

        spigot_address = address(line.spigot());
        spigot = Spigot(payable(spigot_address));

        escrow_address = address(line.escrow());
        escrow = Escrow(payable(escrow_address));
    }

    function test_deployed_lines_own_modules() public {
        assertEq(spigot.owner(), line_address);
        assertEq(escrow.line(), line_address);
    }

    function test_arbiter_cant_be_null() public {
        vm.expectRevert(ILineFactory.InvalidArbiterAddress.selector);
        LineFactory tempLineFactory = new LineFactory(
            address(moduleFactory),
            address(0),
            oracle,
            swapTarget
        );
    }

    function test_deploying_secure_line_with_modules() public {
        // owner, treasury, operator
        address moduleSpigot = moduleFactory.deploySpigot(
            address(this), // owner
            borrower,
            borrower
        );

        // minimumCollateralratio, oracle, line, borrower
        address moduleEscrow = moduleFactory.deployEscrow(
            3000, // cRatio
            oracle,
            address(this), // owner
            borrower
        );

        ILineFactory.CoreLineParams memory coreParams = ILineFactory
            .CoreLineParams({
                borrower: borrower,
                ttl: ttl,
                cratio: 3000,
                revenueSplit: 90
            });

        address moduleLine = lineFactory.deploySecuredLineWithModules(
            coreParams,
            moduleSpigot,
            moduleEscrow
        );

        ISpigot(moduleSpigot).updateOwner(moduleLine);
        IEscrow(moduleEscrow).updateLine(moduleLine);

        assertEq(ISpigot(moduleSpigot).owner(), moduleLine);
        assertEq(IEscrow(moduleEscrow).line(), moduleLine);
    }

    // TODO: add a test for "forgetting" to transfer ownership and the repercussions

    function test_new_line_has_correct_spigot_and_escrow() public {
        assertEq(spigot.owner(), line_address);
        assertEq(escrow.line(), line_address);
        assertEq(address(line.escrow()), address(escrow));
        assertEq(address(line.spigot()), address(spigot));
    }

    // TODO: should use some fuzzing here
    function test_fail_if_revenueSplit_exceeds_100() public {
        // vm.assume( pct > 100)
        ILineFactory.CoreLineParams memory coreParams = ILineFactory
            .CoreLineParams({
                borrower: borrower,
                ttl: ttl,
                cratio: 3000,
                revenueSplit: 110
            });

        vm.expectRevert(ILineFactory.InvalidRevenueSplit.selector);
        address bad_line = lineFactory.deploySecuredLineWithConfig(coreParams);
    }

    function test_newly_deployed_lines_are_always_active() public {
        assertEq(uint256(line.status()), uint256(LineLib.STATUS.ACTIVE));
    }

    function test_default_params_new_line() public {
        assertEq(line.defaultRevenueSplit(), 90);
        assertEq(escrow.minimumCollateralRatio(), 3000);
        assertEq(line.deadline(), block.timestamp + 90 days);
    }

    function test_default_params_escrow() public {
        assertEq(escrow.minimumCollateralRatio(), 3000);
    }

    function test_rollover_params_consistent() public {
        skip(10000);
        address new_line_address = lineFactory.rolloverSecuredLine(
            payable(line_address),
            borrower,
            ttl
        );

        SecuredLine new_line = SecuredLine(payable(new_line_address));
        assertEq(new_line.deadline(), ttl + 10001);
        assertEq(address(new_line.spigot()), address(line.spigot()));
        assertEq(address(new_line.escrow()), address(line.escrow()));
        assertEq(new_line.defaultRevenueSplit(), line.defaultRevenueSplit());

        address new_escrow_address = address(new_line.escrow());
        Escrow new_escrow = Escrow(payable(new_escrow_address));

        assertEq(
            new_escrow.minimumCollateralRatio(),
            escrow.minimumCollateralRatio()
        );
    }

    function test_cannot_rollover_if_not_repaid() public {
        skip(10000);
        address new_line_address = lineFactory.rolloverSecuredLine(
            payable(line_address),
            borrower,
            ttl
        );

        vm.startPrank(borrower);
        vm.expectRevert(ISecuredLine.DebtOwed.selector);
        line.rollover(new_line_address);
    }
}
