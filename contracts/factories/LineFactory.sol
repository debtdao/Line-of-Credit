pragma solidity 0.8.9;

import {SecuredLine} from "../modules/credit/SecuredLine.sol";

import {IModuleFactory} from "./IModuleFactory.sol";


contract LineFactory is IModuleFactory {
   
    address factory;
    constructor (
        address moduleFactory
    ) {
        factory = moduleFactory;
    }    

    uint8 defaultRevenueSplit = 90;
    uint32 minCRatio = 3000;
    address arbiter = address(10); // TBD


    event DeployedSecuredLine(
        address line,
        address borrower,
        uint32 minCRatio
    );
    
   
    function DeployEscrow(uint32 minCRatio, address oracle, address owner, address borrower)  external returns(address){
        address escrow = IModuleFactory(factory).DeployEscrow(minCRatio, oracle, owner, borrower);
        emit DeployedEscrow(escrow, minCRatio, borrower);
        return escrow;
    }

    function DeploySpigot(address owner, address treasury, address operator) external returns(address){
        address spigot = IModuleFactory(factory).DeploySpigot(owner, treasury, operator);
        emit DeployedSpigot(spigot, owner, treasury);
        return spigot;
    }
    
    
    function DeploySecuredLine(
        address oracle, 
        address treasury, 
        address operator, 
        address borrower, 
        address owner, 
        uint ttl,
        address swapTarget
        ) public {
            address s = IModuleFactory(factory).DeploySpigot(owner, treasury, operator);
            address e = IModuleFactory(factory).DeployEscrow(minCRatio, oracle, owner, borrower);
            SecuredLine line = new SecuredLine(oracle, arbiter, borrower, payable(swapTarget), address(s), address(e), ttl, defaultRevenueSplit);
            emit DeployedSecuredLine(address(line), borrower, minCRatio);
    }

    function deploySecuredLineWithConfig(
        address oracle, 
        address treasury, 
        address operator, 
        address borrower, 
        address owner, 
        uint ttl, 
        uint8 revenueSplit,
        uint cratio,
        address swapTarget
        ) public {
            address s = IModuleFactory(factory).DeploySpigot(owner, treasury, operator);
            address e = IModuleFactory(factory).DeployEscrow(minCRatio, oracle, owner, borrower);
            SecuredLine line = new SecuredLine(oracle, arbiter, borrower, payable(swapTarget), address(s), address(e), ttl, revenueSplit);
            emit DeployedSecuredLine(address(line), borrower, minCRatio);

    }

    function rolloverSecuredLine(
        address oracle,
        address borrower, 
        address spigot, 
        address escrow, 
        uint ttl ,
        address swapTarget
        ) public {
            SecuredLine line = new SecuredLine(oracle, arbiter, borrower, payable(swapTarget), spigot, escrow, ttl, defaultRevenueSplit);
            emit DeployedSecuredLine(address(line), borrower, minCRatio);

    }
}