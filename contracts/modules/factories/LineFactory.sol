pragma solidity 0.8.9;

import {ILineFactory} from "../../interfaces/ILineFactory.sol";
import {LineFactoryLib} from "../../utils/LineFactoryLib.sol";
import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";

contract LineFactory is ILineFactory {
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
    
    function deploySecuredLineWithModules(
        uint ttl,
        address borrower, 
        address spigot,
        address escrow,
        uint8 revenueSplit
    ) external returns(address, address, address) {
        return LineFactoryLib.deploySecuredLineWithModules(ttl, borrower, spigot, escrow, revenueSplit);

    }

    function deploySecuredLine(
        uint ttl,
        address borrower
    ) external returns(address, address, address) {
        return LineFactoryLib.deploySecuredLine(
          ttl,
          factory,
          borrower,
          defaultRevenueSplit,
          defaultMinCRatio
        );
    }

    function deploySecuredLineWithConfig(
        uint ttl, 
        address oracle, 
        address arbiter,
        address borrower, 
        address payable swapTarget,
        uint8 revenueSplit,
        uint32 cratio
    ) external returns(address, address, address) {
        return LineFactoryLib.deploySecuredLine(
          ttl,
          factory,
          borrower,
          revenueSplit,
          cratio
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
        uint ttl,
        address oracle,
        address arbiter,
        address borrower,
        address payable oldLine
    ) external returns(address, address, address) {
        return LineFactoryLib.rolloverSecuredLine(ttl, oracle, arbiter, borrower, oldLine);
    }
}
