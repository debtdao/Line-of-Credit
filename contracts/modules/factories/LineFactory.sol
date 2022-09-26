pragma solidity 0.8.9;

import {ILineFactory} from "../../interfaces/ILineFactory.sol";
import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";
import {LineLib} from "../../utils/LineLib.sol";
import {LineFactoryLib} from "../../utils/LineFactoryLib.sol";

contract LineFactory is ILineFactory {

    IModuleFactory immutable factory;
    address immutable factory;
    uint8 constant defaultRevenueSplit = 90; // 90% to debt repayment
    uint32 constant defaultMinCRatio = 3000; // 30.00% minimum collateral ratio
 

    constructor (address factory_) {
        factory = factory_;
    }    
    
   
    function deployEscrow(uint32 minCRatio, address oracle_, address owner, address borrower)  external returns(address){
        address escrow = IModuleFactory(factory).deployEscrow(minCRatio, oracle_, owner, borrower);
        return escrow;
    }

    function deploySpigot(address owner, address borrower, address operator) external returns(address){
        address spigot = IModuleFactory(factory).deploySpigot(owner, borrower, operator);
        return spigot;
    }
    
    function deploySecuredLine(
        address oracle,
        address arbiter,
        address borrower, 
        address owner, 
        uint ttl,
        address payable swapTarget
    ) external returns(bool) {
        address oracle_ = oracle; // gas savings
        // deploy new modules
        address s = IModuleFactory(factory).deploySpigot(address(this), borrower, borrower);
        address e = IModuleFactory(factory).deployEscrow(defaultMinCRatio, oracle, address(this), borrower);
        SecuredLine line = LineFactoryLib.deploySecuredLine(oracle, arbiter, borrower, swapTarget,s, e, ttl, defaultRevenueSplit);
        // give modules from address(this) to line so we can run line.init()
        LineFactoryLib.transferModulesToLine(address(line), s, e);
        emit DeployedSecuredLine(address(line), s, e, swapTarget);
        if(line.init() != LineLib.STATUS.ACTIVE) {
          revert InitNewLineFailed(address(line), s, e);
        }
        return true;
    }

    function deploySecuredLineWithConfig(
        address oracle, 
        address arbiter,
        address borrower, 
        address operator, 
        address owner, 
        uint ttl, 
        uint8 revenueSplit,
        uint32 cratio,
        address payable swapTarget
    ) external returns(bool) {
        address s = factory.deploySpigot(owner, borrower, operator);
        address e = factory.deployEscrow(cratio, oracle, owner, borrower);
        SecuredLine line = LineFactoryLib.deploySecuredLine(oracle, arbiter, borrower, swapTarget,s, e, ttl, revenueSplit);
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
        address oracle,
        address arbiter,
        address payable oldLine,
        address borrower, 
        uint ttl
    ) external returns(address) {
        LineFactoryLib.rolloverSecuredLine(oldLine, borrower, ttl, oracle, arbiter);
    }

}
