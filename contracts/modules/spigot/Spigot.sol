pragma solidity 0.8.9;

import { ReentrancyGuard } from "openzeppelin/security/ReentrancyGuard.sol";
import { LineLib } from  "../../utils/LineLib.sol";
import { SpigotState, SpigotLib } from  "../../utils/SpigotLib.sol";

import {ISpigot} from "../../interfaces/ISpigot.sol";

/**
 * @title   Spigot
 * @author  Kiba Gateaux
 * @notice  A contract allowing the revenue stream of a smart contract (revenue contract) to be split in a secure way between two or more parties 
            according to an agreement between the parties
 * @dev     Should be deployed once per agreement. Multiple revenue contracts can be attached to a Spigot.
 */
contract Spigot is ISpigot, ReentrancyGuard {
    using SpigotLib for SpigotState;

    // Stakeholder variables
    
    SpigotState private state;

    /**
     *
     * @dev             Configure data for contract owners and initial revenue contracts.
                        Owner/operator/treasury can all be the same address when setting up a Spigot
     * @param _owner    An address of Party A that controls the Spigot and owns rights to some or all of the revenue tokens from the revenue contract
                        on behalf of itself or a 3rd party and in exchange for some consideration due to Party B
     * @param _operator An address through which Party B able to execute whitelisted functions to carry on business as usual 
                        related to revenue generating contract controlled by the Spigot.
     * @param _treasury The Treasury of Party B. It receives revenue tokens that don't accrue to the Owner
 
     *
     */
    constructor (
        address _owner,
        address _treasury,
        address _operator
    ) {
        state.owner = _owner;
        state.operator = _operator;
        state.treasury = _treasury;
    }

    function owner() public view returns (address) {
        return state.owner;
    }

    function operator() public view returns (address) {
        return state.operator;
    }

    function treasury() public view returns (address) {
        return state.treasury;
    }

    // ##########################
    // #####   Claimoooor   #####
    // ##########################

    /**

     * @notice - Claims revenue tokens from the Spigot (push and pull) and makes them available to a Lender for later withdrawal.
                 Calls predefined function in contract settings to claim revenue.
                 Automatically sends portion to treasury and escrows Owner's share
                 N.B. There is no conversion (trade) to the credit token in this case. 
     * @dev      - callable by anyone
     * @param   revenueContract Contract with registered settings to claim revenue from
     * @param data  Transaction data, including function signature, to properly claim revenue on revenueContract
     * @return claimed -  The amount of revenue tokens claimed from revenueContract and split between `owner` and `treasury`
    */
    function claimRevenue(address revenueContract, bytes calldata data)
        external nonReentrant
        returns (uint256 claimed)
    {
        return state.claimRevenue(revenueContract, data);
    }


    /**
     * @notice - Allows Spigot Owner to claim escrowed revenue tokens from a revenue contract
     * @dev - callable by `owner`
     * @param token Revenue token that is being escrowed by spigot
     * @return claimed -  The amount of tokens claimed from revenue by the `owner`

    */
    function claimEscrow(address token)
        external
        nonReentrant
        returns (uint256 claimed) 
    {
        return state.claimEscrow(token);
    }


    // ##########################
    // ##### *ring* *ring*  #####
    // #####  OPERATOOOR    #####
    // #####  OPERATOOOR    #####
    // ##########################

    /**
     * @notice - Allows Operator to call whitelisted functions on revenue contracts to maintain their product
     *           while still allowing Spigot Owner to receive its revenue stream
     * @dev - callable by `operator`
     * @param revenueContract - smart contract to call
     * @param data - tx data, including function signature, to call contract with
     */
    function operate(address revenueContract, bytes calldata data) external returns (bool) {
        return state.operate(revenueContract, data);
    }



    // ##########################
    // #####  Maintainooor  #####
    // ##########################

    /**
     * @notice Allows Owner to add a new revenue stream to the Spigot
     * @dev - callable by `owner`
     * @param revenueContract - smart contract to claim tokens from
     * @param setting - Spigot settings for smart contract   
     */
    function addSpigot(address revenueContract, Setting memory setting) external returns (bool) {
        return state.addSpigot(revenueContract, setting);
    }

    /**

     * @notice - changes control over a single revenue generating contract from its then Owner (A) to another actor (typically the Operator/Borrower)
     *           sends any escrowed tokens to the prior Owner A.
     * @dev - callable by `owner`
     * @param revenueContract - smart contract to transfer ownership of
     */
    function removeSpigot(address revenueContract)
        external
        returns (bool)
    {
       return state.removeSpigot(revenueContract);
    }
    // Changes the revenue split between the Treasury and the Owner based upon the status of the Line of Credit
    // or otherwise if the Owner and Borrower wish to change the split.
    function updateOwnerSplit(address revenueContract, uint8 ownerSplit)
        external
        returns(bool)
    {
      return state.updateOwnerSplit(revenueContract, ownerSplit);
    }

    /**
     * @notice - Update Owner role of Spigot contract.
     *      New Owner receives revenue stream split and can control Spigot
     * @dev - callable by `owner`
     * @param newOwner - Address to give control to
     */
    function updateOwner(address newOwner) external returns (bool) {
        return state.updateOwner(newOwner);
    }

    /**

     * @notice - Update Operator role of Spigot contract.
     *      New Operator can interact with revenue contracts.
     * @dev - callable by `operator`
     * @param newOperator - Address to give control to
     */
    function updateOperator(address newOperator) external returns (bool) {
        return state.updateOperator(newOperator);
    }
    
    /**

     * @notice - Update Treasury role of Spigot contract.
     *      New Treasury receives revenue stream split
     * @dev - callable by `treasury`
     * @param newTreasury - Address to divert funds to
     */
    function updateTreasury(address newTreasury) external returns (bool) {
        return state.updateTreasury(newTreasury);
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
        return state.updateWhitelistedFunction(func, allowed);
    }

    // ##########################
    // #####   GETTOOOORS   #####
    // ##########################

    /**
     * @notice - Retrieve amount of revenue tokens escrowed waiting for claim
     * @param token Revenue token that is being garnished from spigots
    */
    function getEscrowed(address token) external view returns (uint256) {
        return state.getEscrowed(token);
    }

    /**
     * @notice - Returns the list of whitelisted functions that an Operator is allowed to perform
                 on the revenue generating smart contracts whilst the Spigot is attached.
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
