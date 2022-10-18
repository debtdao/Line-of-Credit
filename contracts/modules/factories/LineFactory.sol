pragma solidity 0.8.9;

import {ILineFactory} from "../../interfaces/ILineFactory.sol";
import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";
import {LineLib} from "   ../../utils/LineLib.sol";
import {LineFactoryLib} from "../../utils/LineFactoryLib.sol";
import {SecuredLine} from "../credit/SecuredLine.sol";

contract LineFactory is ILineFactory {
    IModuleFactory immutable factory;

    uint8 constant defaultRevenueSplit = 90; // 90% to debt repayment
    uint8 constant MAX_SPLIT = 100; // max % to take
    uint32 constant defaultMinCRatio = 3000; // 30.00% minimum collateral ratio

    constructor(address moduleFactory) {
        factory = IModuleFactory(moduleFactory);
    }

    function deployEscrow(uint32 minCRatio, address oracle_, address owner, address borrower)
        external
        returns (address)
    {
        return factory.deployEscrow(minCRatio, oracle_, owner, borrower);
    }

    function deploySpigot(address owner, address borrower, address operator) external returns (address) {
        return factory.deploySpigot(owner, borrower, operator);
    }

    function deploySecuredLine(
        address oracle,
        address arbiter,
        address borrower,
        uint256 ttl,
        address payable swapTarget
    ) external returns (address line) {
        // deploy new modules
        address s = factory.deploySpigot(address(this), borrower, borrower);
        address e = factory.deployEscrow(defaultMinCRatio, oracle, address(this), borrower);
        uint8 split = defaultRevenueSplit; // gas savings
        line = LineFactoryLib.deploySecuredLine(oracle, arbiter, borrower, swapTarget, s, e, ttl, split);
        // give modules from address(this) to line so we can run line.init()
        LineFactoryLib.transferModulesToLine(address(line), s, e);
        emit DeployedSecuredLine(address(line), s, e, swapTarget, split);
        return line;
    }

    function deploySecuredLineWithConfig(
        address oracle,
        address arbiter,
        address borrower,
        uint256 ttl,
        uint8 revenueSplit,
        uint32 cratio,
        address payable swapTarget
    ) external returns (address line) {
        if (revenueSplit > MAX_SPLIT) revert InvalidRevenueSplit();
        // deploy new modules
        address s = factory.deploySpigot(address(this), borrower, borrower);
        address e = factory.deployEscrow(cratio, oracle, address(this), borrower);
        line = LineFactoryLib.deploySecuredLine(oracle, arbiter, borrower, swapTarget, s, e, ttl, revenueSplit);
        // give modules from address(this) to line so we can run line.init()
        LineFactoryLib.transferModulesToLine(address(line), s, e);
        emit DeployedSecuredLine(address(line), s, e, swapTarget, revenueSplit);
        return line;
    }

    /**
     * @notice sets up new line based of config of old line. Old line does not need to have REPAID status for this call to succeed.
     *   @dev borrower must call rollover() on `oldLine` with newly created line address
     *   @param oldLine  - line to copy config from for new line.
     *   @param borrower - borrower address on new line
     *   @param ttl      - set total term length of line
     *   @return newLine - address of newly deployed line with oldLine config
     */
    function rolloverSecuredLine(
        address payable oldLine,
        address borrower,
        address oracle,
        address arbiter,
        uint256 ttl
    ) external returns (address) {
        LineFactoryLib.rolloverSecuredLine(oldLine, borrower, oracle, arbiter, ttl);
    }
}
