pragma solidity 0.8.9;

import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";

import {Spigot} from "../spigot/Spigot.sol";
import {Escrow} from "../escrow/Escrow.sol";

contract Factory is IModuleFactory {    
    function deploySpigot(address owner, address treasury, address operator) external returns (address){
        address spigot = address(new Spigot(owner, treasury, operator));
        emit DeployedSpigot(spigot, owner, treasury, operator);
        return spigot;
    }

    function deployEscrow(uint32 minCRatio, address oracle, address owner, address borrower) external returns(address){
        address escrow = address(new Escrow(minCRatio, oracle, owner, borrower));
        emit DeployedEscrow(escrow, minCRatio, borrower, owner);
        return escrow;
    }   
}
