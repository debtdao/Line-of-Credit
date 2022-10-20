import "forge-std/Test.sol";

import {Denominations} from "chainlink/Denominations.sol";

import {MockReceivables} from "../mock/MockReceivables.sol";
import {RevenueToken} from "../mock/RevenueToken.sol";
import {RevenueToken4626} from "../mock/RevenueToken4626.sol";

import {LineLib} from "../utils/LineLib.sol";
import {CreditLib} from "../utils/CreditLib.sol";
import {LineFactory} from "../modules/factories/LineFactory.sol";
import {ILineFactory} from "../interfaces/ILineFactory.sol";
import {ModuleFactory} from "../modules/factories/ModuleFactory.sol";

contract LineFactoryAltTest is Test {
    LineFactory lineFactory;
    ModuleFactory moduleFactory;

    address lender = makeAddr("lender");
    address treasury = makeAddr("treasury");
    address oracle = address(0xdebf);
    address arbiter = address(0xf1c0);
    address borrower = address(0xbA05);
    address swapTarget = address(0xb0b0);
    uint256 ttl = 90 days;

    address deployedSpigot;
    address deployedEscrow;

    address lineOfCredit;

    function setUp() public {
        moduleFactory = new ModuleFactory();
        // lineFactory = new LineFactory(
        //     address(moduleFactory),
        //     arbiter,
        //     oracle,
        //     swapTarget
        // );
    }

    function test_deploy_line_with_modules() public {
        lineOfCredit = _deployLineOfCredit();
    }

    function _deployLineOfCredit() internal returns (address securedLine) {
        // deploy the spigot and escrow contracts
        deployedSpigot = moduleFactory.deploySpigot(lender, borrower, borrower);
        deployedEscrow = moduleFactory.deployEscrow(
            0,
            oracle,
            address(this),
            borrower
        );

        // deploy the line factoryy
        lineFactory = new LineFactory(
            address(moduleFactory),
            arbiter,
            oracle,
            swapTarget
        );

        // deploy a line of credit using the existing spigot and escrow

        ILineFactory.CoreLineParams memory coreParams = ILineFactory
            .CoreLineParams({
                borrower: borrower,
                ttl: ttl,
                cratio: 0,
                revenueSplit: 50
            });

        securedLine = lineFactory.deploySecuredLineWithModules(
            coreParams,
            deployedSpigot,
            deployedEscrow
        );
    }
}
