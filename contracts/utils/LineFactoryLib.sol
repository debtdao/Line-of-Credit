pragma solidity 0.8.9;

import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {LineLib} from "./LineLib.sol";

library LineFactoryLib {
    event DeployedSecuredLine(
        address indexed deployedAt,
        address indexed escrow,
        address indexed spigot,
        address swapTarget,
        uint8 revenueSplit
    );

    event DeployedSpigot(address indexed deployedAt, address indexed owner, address operator);
    event DeployedEscrow(address indexed deployedAt, uint32 indexed minCRatio, address indexed oracle, address owner);
    error ModuleTransferFailed(address line, address spigot, address escrow);
    error InitNewLineFailed(address line, address spigot, address escrow);

    /**
     * @notice  - transfer ownership of Spigot + Escrow contracts from factory to line contract after all 3 have been deployed
     * @param line    - the line to transfer modules to
     * @param spigot  - the module to be transferred to line
     * @param escrow  - the module to be transferred to line
    */
    function transferModulesToLine(address line, address spigot, address escrow) external {
        (bool success, bytes memory returnVal) = spigot.call(
            abi.encodeWithSignature("updateOwner(address)", address(line))
        );
        (bool success2, bytes memory returnVal2) = escrow.call(
            abi.encodeWithSignature("updateLine(address)", address(line))
        );

        // ensure all modules were transferred
        if (!(success && abi.decode(returnVal, (bool)) && success2 && abi.decode(returnVal2, (bool)))) {
            revert ModuleTransferFailed(line, spigot, escrow);
        }

        if (SecuredLine(payable(line)).init() != LineLib.STATUS.ACTIVE) {
            revert InitNewLineFailed(address(line), spigot, escrow);
        }
    }
    /**
     * @notice  - See SecuredLine.constructor(). Deploys a new SecuredLine contract with params provided by factory.
     * @return line   - address of newly deployed line
    */
    function deploySecuredLine(
        address oracle,
        address arbiter,
        address borrower,
        address payable swapTarget,
        address s,
        address e,
        uint256 ttl,
        uint8 revenueSplit
    ) external returns (address) {
        return address(new SecuredLine(oracle, arbiter, borrower, swapTarget, s, e, ttl, revenueSplit));
    }
}