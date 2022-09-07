pragma solidity 0.8.9;

import {Spigot} from "../modules/spigot/Spigot.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";

contract Factory {

    Spigot[] public SpigotArray;
    Escrow[] public EscrowArray;
    
    
    function DeploySpigot(address owner, address treasury, address operator) public virtual returns(address){
        Spigot spigot = new Spigot(owner, treasury, operator);
        SpigotArray.push(spigot);
        address s = address(spigot);
        return address(s);
    }

    function DeployEscrow(uint minCRatio, address oracle, address owner, address borrower) public virtual returns(address){
        Escrow escrow = new Escrow(minCRatio, oracle, owner, borrower);
        EscrowArray.push(escrow);
        address e = address(escrow);
        return e;
    }  
    
}