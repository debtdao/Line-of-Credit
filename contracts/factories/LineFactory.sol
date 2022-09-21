pragma solidity 0.8.9;

import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {LineLib} from "../utils/LineLib.sol";

import {ILineFactory} from "../interfaces/ILineFactory.sol";
import {IModuleFactory} from "../interfaces/IModuleFactory.sol";


contract LineFactory is ILineFactory {
    IModuleFactory immutable factory;

    uint8 constant defaultRevenueSplit = 90; // 90% to debt repayment
    uint32 constant defaultMinCRatio = 3000; // 30.00% minimum collateral ratio
    address arbiter;
    address oracle;

    constructor (address moduleFactory, address arbiter_, address oracle_) {
        factory = IModuleFactory(moduleFactory);
        arbiter = arbiter_;
        oracle = oracle_;
    }    

    function updateArbiter(address arbiter_) external {
      require(msg.sender == arbiter);
      arbiter = arbiter_;
    }

    function updateOracle(address oracle_) external {
      require(msg.sender == arbiter);
      oracle = oracle_;
    }
   
    function DeployEscrow(uint32 minCRatio, address oracle_, address owner, address borrower)  external returns(address){
        address escrow = factory.DeployEscrow(minCRatio, oracle_, owner, borrower);
        emit DeployedEscrow(escrow, minCRatio, oracle_, owner);
        return escrow;
    }

    function DeploySpigot(address owner, address borrower, address operator) external returns(address){
        address spigot = factory.DeploySpigot(owner, borrower, operator);
        emit DeployedSpigot(spigot, owner, borrower, operator);
        return spigot;
    }
    
    function DeploySecuredLine(
        address borrower, 
        address owner, 
        uint ttl,
        address payable swapTarget
    ) external returns(bool) {
        address oracle_ = oracle; // gas savings
        // deploy new modules
        address s = factory.DeploySpigot(address(this), borrower, borrower);
        address e = factory.DeployEscrow(defaultMinCRatio, oracle_, address(this), borrower);
        SecuredLine line = new SecuredLine(oracle_, arbiter, borrower, swapTarget, s, e, ttl, defaultRevenueSplit);
        // give modules from address(this) to line so we can run line.init()
        _transferModulesToLine(address(line), s, e);
        
        emit DeployedSpigot(s, address(this), borrower, borrower);
        emit DeployedEscrow(e, defaultMinCRatio, oracle_, owner);
        emit DeployedSecuredLine(address(line), s, e, swapTarget);
        if(line.init() != LineLib.STATUS.ACTIVE) {
          revert InitNewLineFailed(address(line), s, e);
        }
        return true;
    }

    function deploySecuredLineWithConfig(
        address oracle, 
        address borrower, 
        address operator, 
        address owner, 
        uint ttl, 
        uint8 revenueSplit,
        uint32 cratio,
        address payable swapTarget
    ) external returns(bool) {
        address s = factory.DeploySpigot(owner, borrower, operator);
        address e = factory.DeployEscrow(cratio, oracle, owner, borrower);
        SecuredLine line = new SecuredLine(oracle, arbiter, borrower, swapTarget, address(s), address(e), ttl, revenueSplit);
        emit DeployedSecuredLine(address(line), s, e, swapTarget);
        if(line.init() != LineLib.STATUS.ACTIVE) {
          revert InitNewLineFailed(address(line), s, e);
        }
        return true;
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
        uint ttl
    ) external returns(address) {
        address s = address(SecuredLine(oldLine).spigot());
        address e = address(SecuredLine(oldLine).escrow());
        address payable st = SecuredLine(oldLine).swapTarget();
        SecuredLine line = new SecuredLine(oracle, arbiter, borrower, st, s, e, ttl, SecuredLine(oldLine).defaultRevenueSplit());
        emit DeployedSecuredLine(address(line), s, e, st);
        if(line.init() != LineLib.STATUS.ACTIVE) {
          revert InitNewLineFailed(address(line), s, e);
        }
        return address(line);
    }

    function _transferModulesToLine(address line, address spigot, address escrow) internal {
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
        if(!(success && res && success2 && res2)) {
          revert ModuleTransferFailed(line, spigot, escrow);
        }
    }

}
