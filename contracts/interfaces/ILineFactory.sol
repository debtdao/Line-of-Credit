pragma solidity 0.8.9;

import { IModuleFactory } from "./IModuleFactory.sol";

interface ILineFactory is IModuleFactory {

    event DeployedSecuredLine(
        address indexed deployedAt,
        address indexed escrow,
        address indexed spigot,
        address swapTarget
    );

    error ModuleTransferFailed(address line, address spigot, address escrow);
    error InitNewLineFailed(address line, address spigot, address escrow);

    function deploySecuredLine(
        address oracle,
        address arbiter,
        address borrower, 
        uint ttl,
        address payable swapTarget
    ) external returns(address);

    function deploySecuredLineWithConfig(
        address oracle, 
        address arbiter,
        address borrower, 
        uint ttl, 
        uint8 revenueSplit,
        uint32 cratio,
        address payable swapTarget
    ) external returns(address);
}
