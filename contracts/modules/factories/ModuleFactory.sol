pragma solidity 0.8.16;

import {Clones} from  "openzeppelin/proxy/Clones.sol";

import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";

import {Spigot} from "../spigot/Spigot.sol";
import {Escrow} from "../escrow/Escrow.sol";

/**
 * @title   - Debt DAO Module Factory
 * @author  - Mom
 * @notice  - Facotry contract to deploy Spigot, and Escrow contracts.
 */
contract ModuleFactory is IModuleFactory {
    address spigotImpl;
    
    constructor() {
        spigotImpl = address(new Spigot());
    }

    /**
     * see Spigot.constructor
     * @notice - Deploys a Spigot module that can be used in a LineOfCredit
     */
    function deploySpigot(address owner, address operator) external returns (address module) {
        module = Clones.clone(spigotImpl);
        Spigot(payable(module)).initialize(owner, operator);
        emit DeployedSpigot(module, owner, operator);
    }

    /**
     * see Escrow.constructor
     * @notice - Deploys an Escrow module that can be used in a LineOfCredit
     */
    function deployEscrow(
        uint32 minCRatio,
        address oracle,
        address owner,
        address borrower
    ) external returns (address module) {
        module = address(new Escrow(minCRatio, oracle, owner, borrower));
        emit DeployedEscrow(module, minCRatio, oracle, owner);
    }
}
