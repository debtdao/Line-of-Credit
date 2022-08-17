pragma solidity 0.8.9;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { LineLib } from  "../../utils/LineLib.sol";

import {ISpigot} from "../../interfaces/ISpigot.sol";

/**
 * @title Spigot
 * @author Kiba Gateaux
 * @notice Contract allowing Owner to secure revenue streams from a DAO and split payments between them
 * @dev Should be deployed once per line. Can attach multiple revenue contracts
 */
contract Spigot is ISpigot, ReentrancyGuard {

    // Constants 

    // Maximum numerator for Setting.ownerSplit param
    uint8 constant MAX_SPLIT =  100;
    // cap revenue per claim to avoid overflows on multiplication when calculating percentages
    uint256 constant MAX_REVENUE = type(uint).max / MAX_SPLIT;

    // Stakeholder variables
    
    address public owner;

    address public operator;

    address public treasury;

    // Spigot variables

    // Total amount of tokens escrowed by spigot
    mapping(address => uint256) private escrowed; // token  -> amount escrowed
    //  allowed by operator on all revenue contracts
    mapping(bytes4 => bool) private whitelistedFunctions; // function -> allowed
    // Configurations for revenue contracts to split
    mapping(address => Setting) private settings; // revenue contract -> settings

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

    modifier whileNoUnclaimedRevenue(address token) {
      // if excess revenue sitting in Spigot after MAX_REVENUE cut,
      // prevent actions until all revenue claimed and escrow updated
      // only protects push payments not pull payments.
      if( LineLib.getBalance(token) > escrowed[token]) {
        revert UnclaimedRevenue();
      }
      _;
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
        address token = settings[revenueContract].token;
        claimed = _claimRevenue(revenueContract, data, token);

        // split revenue stream according to settings
        uint256 escrowedAmount = claimed * settings[revenueContract].ownerSplit / 100;
        // update escrowed balance
        escrowed[token] = escrowed[token] + escrowedAmount;
        
        // send non-escrowed tokens to Treasury if non-zero
        if(claimed > escrowedAmount) {
            require(LineLib.sendOutTokenOrETH(token, treasury, claimed - escrowedAmount));
        }

        emit ClaimRevenue(token, claimed, escrowedAmount, revenueContract);
        
        return claimed;
    }


     function _claimRevenue(address revenueContract, bytes calldata data, address token)
        internal
        returns (uint256 claimed)
    {
        uint256 existingBalance = LineLib.getBalance(token);
        if(settings[revenueContract].claimFunction == bytes4(0)) {
            // push payments
            // claimed = total balance - already accounted for balance
            claimed = existingBalance - escrowed[token];
        } else {
            // pull payments
            if(bytes4(data) != settings[revenueContract].claimFunction) { revert BadFunction(); }
            (bool claimSuccess,) = revenueContract.call(data);
            if(!claimSuccess) { revert ClaimFailed(); }
            // claimed = total balance - existing balance
            claimed = LineLib.getBalance(token) - existingBalance;
        }

        if(claimed == 0) { revert NoRevenue(); }

        // cap so uint doesnt overflow in split calculations.
        // can sweep by "attaching" a push payment spigot with same token
        if(claimed > MAX_REVENUE) claimed = MAX_REVENUE;

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
        whileNoUnclaimedRevenue(token)
        returns (uint256 claimed) 
    {
        if(msg.sender != owner) { revert CallerAccessDenied(); }
        
        claimed = escrowed[token];

        if(claimed == 0) { revert ClaimFailed(); }

        LineLib.sendOutTokenOrETH(token, owner, claimed);

        escrowed[token] = 0; // keep 1 in escrow for recurring call gas optimizations?

        emit ClaimEscrow(token, claimed, owner);

        return claimed;
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
        return _operate(revenueContract, data);
    }

    /**
     * @notice - Checks that operation is whitelisted by Spigot Owner and calls revenue contract with supplied data
     * @param revenueContract - smart contracts to call
     * @param data - tx data, including function signature, to call contracts with
     */
    function _operate(address revenueContract, bytes calldata data) internal nonReentrant returns (bool) {
        bytes4 func = bytes4(data);
        // extract function signature from tx data and check whitelist
        if(!whitelistedFunctions[func]) { revert BadFunction(); }
        // cant claim revenue via operate() because that fucks up accounting logic. Owner shouldn't whitelist it anyway but just in case
        if(
          func == settings[revenueContract].claimFunction ||
          func == settings[revenueContract].transferOwnerFunction
        ) { revert BadFunction(); }

        (bool success,) = revenueContract.call(data);
        if(!success) { revert BadFunction(); }

        return true;
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
        return _addSpigot(revenueContract, setting);
    }

    /**
     * @notice Checks  revenue contract doesn't already have spigot
     *      then registers spigot configuration for revenue contract
     * @param revenueContract - smart contract to claim tokens from
     * @param setting - spigot configuration for smart contract   
     */
    function _addSpigot(address revenueContract, Setting memory setting) internal returns (bool) {
        require(revenueContract != address(this));
        // spigot setting already exists
        require(settings[revenueContract].transferOwnerFunction == bytes4(0));
        
        // must set transfer func
        if(setting.transferOwnerFunction == bytes4(0)) { revert BadSetting(); }
        if(setting.ownerSplit > MAX_SPLIT) { revert BadSetting(); }
        if(setting.token == address(0)) {  revert BadSetting(); }
        
        settings[revenueContract] = setting;
        emit AddSpigot(revenueContract, setting.token, setting.ownerSplit);

        return true;
    }

    /**

     * @notice - Change owner of revenue contract from Spigot (this contract) to Operator.
     *      Sends existing escrow to current Owner.
     * @dev - callable by `owner`
     * @param revenueContract - smart contract to transfer ownership of
     */
    function removeSpigot(address revenueContract)
        external
        whileNoUnclaimedRevenue(settings[revenueContract].token)
        returns (bool)
    {
        if(msg.sender != owner) { revert CallerAccessDenied(); }
        
        address token = settings[revenueContract].token;
        uint256 claimable = escrowed[token];
        if(claimable > 0) {
            require(LineLib.sendOutTokenOrETH(token, owner, claimable));
            emit ClaimEscrow(token, claimable, owner);
        }
        
        (bool success,) = revenueContract.call(
            abi.encodeWithSelector(
                settings[revenueContract].transferOwnerFunction,
                operator    // assume function only takes one param that is new owner address
            )
        );
        require(success);

        delete settings[revenueContract];
        emit RemoveSpigot(revenueContract, token);

        return true;
    }

    function updateOwnerSplit(address revenueContract, uint8 ownerSplit)
        external
        whileNoUnclaimedRevenue(settings[revenueContract].token)
        returns(bool)
    {
      if(msg.sender != owner) { revert CallerAccessDenied(); }
      if(ownerSplit > MAX_SPLIT) { revert BadSetting(); }

      settings[revenueContract].ownerSplit = ownerSplit;
      emit UpdateOwnerSplit(revenueContract, ownerSplit);
      
      return true;
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
        if(msg.sender != owner) { revert CallerAccessDenied(); }
        whitelistedFunctions[func] = allowed;
        emit UpdateWhitelistFunction(func, allowed);
        return true;
    }

    // ##########################
    // #####   GETTOOOORS   #####
    // ##########################

    /**
     * @notice - Retrieve amount of tokens tokens escrowed waiting for claim
     * @param token Revenue token that is being garnished from spigots
    */
    function getEscrowed(address token) external view returns (uint256) {
        return escrowed[token];
    }

    /**
     * @notice - If a function is callable on revenue contracts
     * @param func Function to check on whitelist 
    */

    function isWhitelisted(bytes4 func) external view returns(bool) {
      return whitelistedFunctions[func];
    }

    function getSetting(address revenueContract)
        external view
        returns(address, uint8, bytes4, bytes4)
    {
        return (
            settings[revenueContract].token,
            settings[revenueContract].ownerSplit,
            settings[revenueContract].claimFunction,
            settings[revenueContract].transferOwnerFunction
        );
    }

    receive() external payable {
        return;
    }

}
