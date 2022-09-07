pragma solidity 0.8.9;

import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {Factory} from "./Factory.sol";

contract SecuredLineFactory is Factory {

    SecuredLine[] public SecuredLineArray;
  

    uint8 defaultRevenueSplit = 90;
    uint32 defaultCRatio = 3000;
    address arbiter = address(10); // TBD
    
   
    function DeployEscrow(address oracle, address owner, address borrower)  public returns(address){
        return Factory.DeployEscrow(defaultCRatio, oracle, owner, borrower);
    }

    function DeploySpigot(address owner, address treasury, address operator) override public returns(address){
        return Factory.DeploySpigot(owner, treasury, operator);
    }

    function test() public returns (string memory){
        return "Does this work?";
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
            address s = DeploySpigot(owner, treasury, operator);
            address e = DeployEscrow(defaultCRatio, oracle, owner, borrower);
            SecuredLine line = new SecuredLine(oracle, arbiter, borrower, payable(swapTarget), address(s), address(e), ttl, defaultRevenueSplit);
            SecuredLineArray.push(line);
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
            address s = DeploySpigot(owner, treasury, operator);
            address e = DeployEscrow(cratio, oracle, owner, borrower);
            SecuredLine line = new SecuredLine(oracle, arbiter, borrower, payable(swapTarget), address(s), address(e), ttl, revenueSplit);
            SecuredLineArray.push(line);

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
            SecuredLineArray.push(line);

    }
}