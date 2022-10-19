pragma solidity 0.8.9;

import {IModuleFactory} from "./IModuleFactory.sol";

interface ILineFactory is IModuleFactory {
    event DeployedSecuredLine(
        address indexed deployedAt,
        address indexed escrow,
        address indexed spigot,
        address swapTarget,
        uint8 revenueSplit
    );

    error ModuleTransferFailed(address line, address spigot, address escrow);
    error InvalidRevenueSplit();

    function deploySecuredLine(address borrower, uint256 ttl)
        external
        returns (address);

    function deploySecuredLineWithConfig(
        address borrower,
        uint256 ttl,
        uint8 revenueSplit,
        uint32 cratio
    ) external returns (address);

    function rolloverSecuredLine(address payable oldLine, uint256 ttl)
        external
        returns (address);
}
