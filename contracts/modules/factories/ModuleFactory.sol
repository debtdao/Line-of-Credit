pragma solidity 0.8.9;

import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";

import {Spigot} from "../spigot/Spigot.sol";
import {Escrow} from "../escrow/Escrow.sol";

contract ModuleFactory is IModuleFactory {    
    function deploySpigot(address owner, address treasury, address operator) external returns (address module){
        module = address(new Spigot(owner, treasury, operator));
        emit DeployedSpigot(module, owner, treasury, operator);
    }

    function deployEscrow(uint32 minCRatio, address oracle, address owner, address borrower) external returns(address module){
        module = address(new Escrow(minCRatio, oracle, owner, borrower));
        emit DeployedEscrow(module, minCRatio, borrower, owner);
    }
    
}
