pragma solidity 0.8.9;

import {SpigotState} from "../../utils/SpigotLib.sol";

contract SpigotBase {
    SpigotState internal spigot;

    /**
     *
     * @dev Configure data for contract owners and initial revenue contracts.
            Owner/operator/treasury can all be the same address
     * @param _owner Third party that owns rights to contract's revenue stream
     * @param _treasury Treasury of DAO that owns contract and receives leftover revenues
     * @param _operator Operational account of DAO that actively manages contract health
     *
     */
    constructor(
        address _owner,
        address _treasury,
        address _operator
    ) {
        spigot.owner = _owner;
        spigot.operator = _operator;
        spigot.treasury = _treasury;
    }
}
