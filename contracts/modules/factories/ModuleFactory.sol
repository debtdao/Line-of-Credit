pragma solidity 0.8.9;

import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";

import {Spigot} from "../spigot/Spigot.sol";
import {Escrow} from "../escrow/Escrow.sol";

contract Factory is IModuleFactory {    

    Spigot spigot;
    Escrow escrow;

    function DeploySpigot(address owner, address treasury, address operator) external returns (address){
        spigot = new Spigot(owner, treasury, operator);
        emit DeployedSpigot(address(spigot), owner, treasury, operator);
        return address(spigot);
    }

    function DeployEscrow(uint32 minCRatio, address oracle, address owner, address borrower) external returns(address){
        escrow = new Escrow(minCRatio, oracle, owner, borrower);
        emit DeployedEscrow(address(escrow), minCRatio, borrower, owner);
        return address(escrow);   
    }
    
}
