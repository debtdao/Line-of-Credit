pragma solidity 0.8.9;

import {Spigot} from "../modules/spigot/Spigot.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";
import {IModuleFactory} from "../interfaces/IModuleFactory.sol";

contract Factory is IModuleFactory {    
    function DeploySpigot(address owner, address treasury, address operator) external returns (address){
        address spigot = address(new Spigot(owner, treasury, operator));
        emit DeployedSpigot(spigot, owner, treasury, operator);
        return address(spigot);
    }

    function DeployEscrow(uint32 minCRatio, address oracle, address owner, address borrower) external returns(address){
        address escrow = address(new Escrow(minCRatio, oracle, owner, borrower));
        emit DeployedEscrow(escrow, minCRatio, oracle, owner);
        return address(escrow);
    }  
    
}
