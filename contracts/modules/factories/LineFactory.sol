pragma solidity 0.8.9;

import {ILineFactory} from "../../interfaces/ILineFactory.sol";
import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";
import {LineLib} from "../../utils/LineLib.sol";
import {LineFactoryLib} from "../../utils/LineFactoryLib.sol";
import {SecuredLine} from "../credit/SecuredLine.sol";

contract LineFactory is ILineFactory {
    IModuleFactory immutable factory;

    uint8 constant defaultRevenueSplit = 90; // 90% to debt repayment
    uint8 constant MAX_SPLIT = 100; // max % to take
    uint32 constant defaultMinCRatio = 3000; // 30.00% minimum collateral ratio

    address public immutable arbiter;
    address public immutable oracle;
    address public immutable swapTarget;

    constructor(
        address moduleFactory,
        address arbiter_,
        address oracle_,
        address swapTarget_
    ) {
        factory = IModuleFactory(moduleFactory);
        arbiter = arbiter_;
        oracle = oracle_;
        swapTarget = swapTarget_;
    }

    function deployEscrow(
        uint32 minCRatio,
        address owner,
        address borrower
    ) external returns (address) {
        return factory.deployEscrow(minCRatio, oracle, owner, borrower);
    }

    function deploySpigot(
        address owner,
        address borrower,
        address operator
    ) external returns (address) {
        return factory.deploySpigot(owner, borrower, operator);
    }

    function deploySecuredLine(address borrower, uint256 ttl)
        external
        returns (address line)
    {
        // deploy new modules
        address s = factory.deploySpigot(address(this), borrower, borrower);
        address e = factory.deployEscrow(
            defaultMinCRatio,
            oracle,
            address(this),
            borrower
        );
        uint8 split = defaultRevenueSplit; // gas savings
        line = LineFactoryLib.deploySecuredLine(
            oracle,
            arbiter,
            borrower,
            payable(swapTarget),
            s,
            e,
            ttl,
            split
        );
        // give modules from address(this) to line so we can run line.init()
        LineFactoryLib.transferModulesToLine(address(line), s, e);
        emit DeployedSecuredLine(address(line), s, e, swapTarget, split);
        return line;
    }

    function deploySecuredLineWithConfig(CoreLineParams calldata coreParams)
        external
        returns (address line)
    {
        if (coreParams.revenueSplit > MAX_SPLIT) {
            revert InvalidRevenueSplit();
        }
        // deploy new modules
        address s = factory.deploySpigot(
            address(this),
            coreParams.borrower,
            coreParams.borrower
        );
        address e = factory.deployEscrow(
            coreParams.cratio,
            oracle,
            address(this),
            coreParams.borrower
        );
        line = LineFactoryLib.deploySecuredLine(
            oracle,
            arbiter,
            coreParams.borrower,
            payable(swapTarget),
            s,
            e,
            coreParams.ttl,
            coreParams.revenueSplit
        );
        // give modules from address(this) to line so we can run line.init()
        LineFactoryLib.transferModulesToLine(address(line), s, e);
        emit DeployedSecuredLine(
            address(line),
            s,
            e,
            swapTarget,
            coreParams.revenueSplit
        );
        return line;
    }

    /// @dev    We don't transfer the modules because the aren't owned by the factory, the responsibility
    ///         falls on the [owner of the line]
    function deploySecuredLineWithModules(
        CoreLineParams calldata coreParams,
        address mSpigot,
        address mEscrow
    ) external returns (address line) {
        line = LineFactoryLib.deploySecuredLine(
            oracle,
            arbiter,
            coreParams.borrower,
            payable(swapTarget),
            mSpigot,
            mEscrow,
            coreParams.ttl,
            coreParams.revenueSplit
        );
    }

    /**
      @notice sets up new line based of config of old line. Old line does not need to have REPAID status for this call to succeed.
      @dev borrower must call rollover() on `oldLine` with newly created line address
      @param oldLine  - line to copy config from for new line.
      @param borrower - borrower address on new line
      @param ttl      - set total term length of line
      @return newLine - address of newly deployed line with oldLine config
     */
    function rolloverSecuredLine(
        address payable oldLine,
        address borrower,
        uint256 ttl
    ) external returns (address) {
        LineFactoryLib.rolloverSecuredLine(
            oldLine,
            borrower,
            oracle,
            arbiter,
            ttl
        );
    }
}
