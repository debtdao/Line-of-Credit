pragma solidity 0.8.9;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { LineLib } from  "../../utils/LineLib.sol";
import { SpigotState, SpigotLib } from  "../../utils/SpigotLib.sol";

import {ISpigot} from "../../interfaces/ISpigot.sol";

/**
 * @title Spigot
 * @author Kiba Gateaux
 * @notice Contract allowing Owner to secure revenue streams from a DAO and split payments between them
 * @dev Should be deployed once per line. Can attach multiple revenue contracts
 */
contract Spigot is ISpigot, ReentrancyGuard {
    using SpigotLib for SpigotState;

    // Stakeholder variables
    
    address public owner;

    address public operator;

    address public treasury;

    SpigotState private state;

    /**
     *
     * @dev Configure data for contract owners and initial revenue contracts.
            Owner/operator/treasury can all be the same address
     * @param _owner Third party that owns rights to contract's revenue stream
     * @param _treasury Treasury of DAO that owns contract and receives leftover revenues
     * @param _operator Operational account of DAO that actively manages contract health
     *
     */
    constructor (
        address _owner,
        address _treasury,
        address _operator
    ) {
        owner = _owner;
        operator = _operator;
        treasury = _treasury;
    }

    // ##########################
    // #####   Claimoooor   #####
    // ##########################

    /**

     * @notice - Claim push/pull payments through Spigots.
                 Calls predefined function in contract settings to claim revenue.
                 Automatically sends portion to treasury and escrows Owner's share.
     * @dev - callable by anyone
     * @param revenueContract Contract with registered settings to claim revenue from
     * @param data  Transaction data, including function signature, to properly claim revenue on revenueContract
     * @return claimed -  The amount of tokens claimed from revenueContract and split in payments to `owner` and `treasury`
    */
    function claimRevenue(address revenueContract, bytes calldata data)
        external nonReentrant
        returns (uint256 claimed)
    {
        address token = state.settings[revenueContract].token;
        claimed = state._claimRevenue(revenueContract, data, token);

        // split revenue stream according to settings
        uint256 escrowedAmount = claimed * state.settings[revenueContract].ownerSplit / 100;
        // update escrowed balance
        state.escrowed[token] = state.escrowed[token] + escrowedAmount;
        
        // send non-escrowed tokens to Treasury if non-zero
        if(claimed > escrowedAmount) {
            require(LineLib.sendOutTokenOrETH(token, treasury, claimed - escrowedAmount));
        }

        emit ClaimRevenue(token, claimed, escrowedAmount, revenueContract);
        
        return claimed;
    }


    /**
     * @notice - Allows Spigot Owner to claim escrowed tokens from a revenue contract
     * @dev - callable by `owner`
     * @param token Revenue token that is being escrowed by spigot
     * @return claimed -  The amount of tokens claimed from revenue garnish by `owner`

    */
    function claimEscrow(address token)
        external
        nonReentrant
        returns (uint256 claimed) 
    {
        return state.claimEscrow(owner, token);
    }


    // ##########################
    // ##### *ring* *ring*  #####
    // #####  OPERATOOOR    #####
    // #####  OPERATOOOR    #####
    // ##########################

    /**
     * @notice - Allows Operator to call whitelisted functions on revenue contracts to maintain their product
     *           while still allowing Spigot Owner to own revenue stream from contract
     * @dev - callable by `operator`
     * @param revenueContract - smart contract to call
     * @param data - tx data, including function signature, to call contract with
     */
    function operate(address revenueContract, bytes calldata data) external returns (bool) {
        if(msg.sender != operator) { revert CallerAccessDenied(); }
        return state._operate(revenueContract, data);
    }



    // ##########################
    // #####  Maintainooor  #####
    // ##########################

    /**
     * @notice Allow owner to add new revenue stream to spigot
     * @dev - callable by `owner`
     * @param revenueContract - smart contract to claim tokens from
     * @param setting - spigot settings for smart contract   
     */
    function addSpigot(address revenueContract, Setting memory setting) external returns (bool) {
        if(msg.sender != owner) { revert CallerAccessDenied(); }
        return state._addSpigot(revenueContract, setting);
    }

    /**

     * @notice - Change owner of revenue contract from Spigot (this contract) to Operator.
     *      Sends existing escrow to current Owner.
     * @dev - callable by `owner`
     * @param revenueContract - smart contract to transfer ownership of
     */
    function removeSpigot(address revenueContract)
        external
        returns (bool)
    {
       return state.removeSpigot(owner, operator, revenueContract);
    }

    function updateOwnerSplit(address revenueContract, uint8 ownerSplit)
        external
        returns(bool)
    {
      return state.updateOwnerSplit(owner, revenueContract, ownerSplit);
    }

    /**
     * @notice - Update Owner role of Spigot contract.
     *      New Owner receives revenue stream split and can control Spigot
     * @dev - callable by `owner`
     * @param newOwner - Address to give control to
     */
    function updateOwner(address newOwner) external returns (bool) {
        if(msg.sender != owner) { revert CallerAccessDenied(); }
        require(newOwner != address(0));
        owner = newOwner;
        emit UpdateOwner(newOwner);
        return true;
    }

    /**

     * @notice - Update Operator role of Spigot contract.
     *      New Operator can interact with revenue contracts.
     * @dev - callable by `operator`
     * @param newOperator - Address to give control to
     */
    function updateOperator(address newOperator) external returns (bool) {
        if(msg.sender != operator) { revert CallerAccessDenied(); }
        require(newOperator != address(0));
        operator = newOperator;
        emit UpdateOperator(newOperator);
        return true;
    }
    
    /**

     * @notice - Update Treasury role of Spigot contract.
     *      New Treasury receives revenue stream split
     * @dev - callable by `treasury`
     * @param newTreasury - Address to divert funds to
     */
    function updateTreasury(address newTreasury) external returns (bool) {
        if(msg.sender != operator && msg.sender != treasury) {
          revert CallerAccessDenied();
        }

        require(newTreasury != address(0));
        treasury = newTreasury;
        emit UpdateTreasury(newTreasury);
        return true;
    }

    /**

     * @notice - Allows Owner to whitelist function methods across all revenue contracts for Operator to call.
     *           Can whitelist "transfer ownership" functions on revenue contracts
     *           allowing Spigot to give direct control back to Operator.
     * @dev - callable by `owner`
     * @param func - smart contract function signature to whitelist
     * @param allowed - true/false whether to allow this function to be called by Operator
     */
     function updateWhitelistedFunction(bytes4 func, bool allowed) external returns (bool) {
        return state.updateWhitelistedFunction(owner, func, allowed);
    }

    // ##########################
    // #####   GETTOOOORS   #####
    // ##########################

    /**
     * @notice - Retrieve amount of tokens tokens escrowed waiting for claim
     * @param token Revenue token that is being garnished from spigots
    */
    function getEscrowed(address token) external view returns (uint256) {
        return state.getEscrowed(token);
    }

    /**
     * @notice - If a function is callable on revenue contracts
     * @param func Function to check on whitelist 
    */

    function isWhitelisted(bytes4 func) external view returns(bool) {
      return state.isWhitelisted(func);
    }

    function getSetting(address revenueContract)
        external view
        returns(address, uint8, bytes4, bytes4)
    {
        return state.getSetting(revenueContract);
    }

    receive() external payable {
        return;
    }

}
