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
        address oracle,
        address arbiter,
        uint ttl
    ) external returns (address) {
        address s = address(SecuredLine(oldLine).spigot());
        address e = address(SecuredLine(oldLine).escrow());
        address payable st = SecuredLine(oldLine).swapTarget();
        uint8 split = SecuredLine(oldLine).defaultRevenueSplit();
        SecuredLine line = new SecuredLine(oracle, arbiter, borrower, st, s, e, ttl, split);
        emit DeployedSecuredLine(address(line), s, e, st, split);
        return address(line);
    }

    function transferModulesToLine(address line, address spigot, address escrow) external {
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
        uint ttl,
        uint8 revenueSplit
    ) external returns (address) {
        return address(new SecuredLine(oracle, arbiter, borrower, swapTarget, s, e, ttl, revenueSplit));
    }
}
