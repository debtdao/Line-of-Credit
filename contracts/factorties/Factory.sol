pragma solidity 0.8.9;

import {Spigot} from "../modules/spigot/Spigot.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";

contract Factory {
    Spigot spigot;
    Escrow escrow;
    Spigot[] public SpigotArray;
    Escrow[] public EscrowArray;
    uint8 defaultRevenueSplit = 90;
    uint32 defaultCRatio = 3000;

    event DeployedSpigot(
        address indexed spigotAddress
    );

    event DeployedEscrow(
        address indexed escrowAddress
    );
    
    function DeploySpigot(address owner, address treasury, address operator) public virtual returns(address){
        spigot = new Spigot(owner, treasury, operator);
        SpigotArray.push(spigot);
        
        emit DeployedSpigot(address(spigot));
    }

    function DeployEscrow(uint8 minCRatio, address oracle, address owner, address borrower) public virtual returns(address){
        escrow = new Escrow(minCRatio, oracle, owner, borrower);
        EscrowArray.push(escrow);
        
        emit DeployedEscrow(address(escrow));
    }  
    
}