pragma solidity 0.8.9;

import { IModuleFactory } from "./IModuleFactory.sol";

interface ILineFactory is IModuleFactory {

    function deploySecuredLine(
        uint ttl,
        address borrower
    ) external returns(address, address, address);

    function deploySecuredLineWithConfig(
        uint ttl, 
        address oracle, 
        address arbiter,
        address borrower, 
        address payable swapTarget,
        uint8 revenueSplit,
        uint32 cratio
    ) external returns(address, address, address);

    function deploySecuredLineWithModules(
        uint ttl, 
        address borrower, 
        address spigot,
        address escrow,
        uint8 revenueSplit
    ) external returns(address, address, address);
}
