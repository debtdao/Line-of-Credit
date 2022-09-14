pragma solidity 0.8.9;

import {Spigot} from "../modules/spigot/Spigot.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";
import {IModuleFactory} from "./IModuleFactory.sol";

contract Factory is IModuleFactory {
    Spigot spigot;
    Escrow escrow;
  
    uint8 defaultRevenueSplit = 90;
    uint32 defaultCRatio = 3000;

   
    
    function DeploySpigot(address owner, address treasury, address operator) external returns (address){
        spigot = new Spigot(owner, treasury, operator);
        emit DeployedSpigot(address(spigot), owner, treasury);
        return address(spigot);
    }

    function DeployEscrow(uint32 minCRatio, address oracle, address owner, address borrower) external returns(address){
        escrow = new Escrow(minCRatio, oracle, owner, borrower);
        emit DeployedEscrow(address(escrow), minCRatio, borrower);
        return address(escrow);
    }  
    
}