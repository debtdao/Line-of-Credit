pragma solidity 0.8.9;

import {LineLib} from "./LineLib.sol";

import {IModuleFactory} from "../interfaces/IModuleFactory.sol";

import {SecuredLine} from "../modules/credit/SecuredLine.sol";


library LineFactoryLib {
    uint8 constant MAX_SPLIT = 100; // max % of revenue to take
    address constant oracle = address(0xbeef);
    address constant arbiter = address(0xbeef);
    address payable constant swapTarget = payable(address(0xbeef));


    event DeployedSecuredLine(
        address indexed deployedAt,
        address indexed escrow,
        address indexed spigot,
        address swapTarget,
        uint8 revenueSplit
    );

    error ModuleTransferFailed(address line, address spigot, address escrow);
    error InitNewLineFailed(address line, address spigot, address escrow);
    error InvalidConfig();


    /**
      @notice Deploys new Secrued Line with defined line and module configs.
      @dev - 
      @param ttl      - set total term length of line
      @param factory  - module factory contract used for deploying new escrow adnd spigot contracts
      @param borrower - borrower address on new line

      @return line - newly deployed contract addresses
      @return spigot - newly deployed contract addresses
      @return escrow - newly deployed contract addresses
     */
    function deploySecuredLine(
        uint ttl,
        address factory,
        address borrower, 
        uint8 revenueSplit,
        uint32 cratio
    ) external returns(address payable line, address spigot, address escrow) {
        if(revenueSplit <= MAX_SPLIT) { revert InvalidConfig(); }

        // deploy new modules
        // give ownership to self bc circular dependency btw module and line address args
        // deploy modules -> deploy line w/ module addresses -> call modules with line address
        spigot = IModuleFactory(factory).deploySpigot(address(this), borrower, borrower);
        escrow = IModuleFactory(factory).deployEscrow(cratio, oracle, address(this), borrower);

        line = payable(address(new SecuredLine(oracle, arbiter, borrower, swapTarget, spigot, escrow, ttl, revenueSplit)));

        // transfer modules from address(this) to line and run line.init()
        _transferModulesAndInitLine(line, spigot, escrow);

        emit DeployedSecuredLine(line, spigot, escrow, swapTarget, revenueSplit);

        return (line, spigot, escrow);
    }

    /**
      @notice - transfer newly deployed modules to a new line and calls .init() on line after transfer
      @dev    - assumes that address(this) is current owner of spigot and escrow.
              - assumes that inputs have been sanitized checking that line esxpects s/e addresses, that its currently uninitialized, etc. 
      @param line   - line to give ownership to
      @param spigot - spigot contract owned by this
      @param escrow - escrow contract owned by this
     */
    function _transferModulesAndInitLine(address payable line, address spigot, address escrow) public {
        (bool success, bytes memory returnVal) = spigot.call(
          abi.encodeWithSignature("updateOwner(address)",
          address(line)
        ));
        (bool success2, bytes memory returnVal2) = escrow.call(
          abi.encodeWithSignature("updateLine(address)",
          address(line)
        ));
        (bool res) = abi.decode(returnVal, (bool));
        (bool res2) = abi.decode(returnVal2, (bool));
        
        // all transfer calls must succeed and return true as expected
        if(!(success && res && success2 && res2)) {
          revert ModuleTransferFailed(line, spigot, escrow);
        }

        if(SecuredLine(line).init() != LineLib.STATUS.ACTIVE) {
          revert InitNewLineFailed(address(line), spigot, escrow);
        }
    }

    /**
      @notice Deploys new Secrued Line with using pre-deployed escrow and spigot. 
      @dev - does NOT ensure that spigot/escrow can be used as collateral on newly deployed line (e.g. already collateral on another line)
           -  so unlike other functions here this means that Lines deployed with  deploySecuredLineWithModules are NOT guaranteed to be viable at deployment.
      @return (line, spigot, escrow) - contract addresses (keep consitent response with other funcs)
     */
    function deploySecuredLineWithModules(
        uint ttl,
        address borrower, 
        address spigot,
        address escrow,
        uint8 revenueSplit
    ) external returns(address, address, address) {
        address line = address(new SecuredLine(oracle, arbiter, borrower, swapTarget, spigot, escrow, ttl, revenueSplit));
        // give modules from address(this) to line so we can run line.init()
        emit DeployedSecuredLine(line, spigot, escrow, swapTarget, revenueSplit);

        return (line, spigot, escrow);
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
        uint ttl,
        address oracle,
        address arbiter,
        address borrower, 
        address payable oldLine
    ) external returns(address, address, address) {
        address s = address(SecuredLine(oldLine).spigot());
        address e = address(SecuredLine(oldLine).escrow());
        address payable st = SecuredLine(oldLine).swapTarget();
        uint8 split = SecuredLine(oldLine).defaultRevenueSplit();
        address line = address(new SecuredLine(oracle, arbiter, borrower, st, s, e, ttl, split));
        emit DeployedSecuredLine(line, s, e, st, split);
        return (line, s, e);
    }


}
