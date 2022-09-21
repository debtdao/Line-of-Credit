pragma solidity 0.8.9;

import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";

import {Spigot} from "../spigot/Spigot.sol";
import {Escrow} from "../escrow/Escrow.sol";

contract Factory is IModuleFactory {    
    function DeploySpigot(address owner, address treasury, address operator) external returns (address){
        return address(new Spigot(owner, treasury, operator));
    }

    function DeployEscrow(uint32 minCRatio, address oracle, address owner, address borrower) external returns(address){
        return address(new Escrow(minCRatio, oracle, owner, borrower));   
    }
    
}
