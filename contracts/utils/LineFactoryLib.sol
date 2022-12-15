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

    function transferModulesToLine(
        address line,
        address spigot,
        address escrow
    ) external {
        (bool success, bytes memory returnVal) = spigot.call(
            abi.encodeWithSignature("updateOwner(address)", address(line))
        );
        (bool success2, bytes memory returnVal2) = escrow.call(
            abi.encodeWithSignature("updateLine(address)", address(line))
        );
        bool res = abi.decode(returnVal, (bool));
        bool res2 = abi.decode(returnVal2, (bool));
        if (!(success && res && success2 && res2)) {
            revert ModuleTransferFailed(line, spigot, escrow);
        }

        if (SecuredLine(payable(line)).init() != LineLib.STATUS.ACTIVE) {
            revert InitNewLineFailed(address(line), spigot, escrow);
        }
    }

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
