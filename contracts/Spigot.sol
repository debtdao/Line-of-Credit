pragma solidity 0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SpigotController is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct SpigotSettings {

        address token;
        uint256 ownerSplit; // x/100 to Owner, rest to Treasury
        uint256 totalEscrowed;
        bytes4 claimFunction;
    }


    // Spigot variables
    mapping(address => SpigotSettings) settings; // revenue contract -> settings

    mapping(bytes4 => bool) whitelistedFunctions; // allowd by operator on all revenue contracts

    event AddSpigot(address indexed revenueContract, address token, uint256 ownerSplit);

    event RemoveSpigot (address indexed revenueContract, address token);

    event UpdateWhitelistFunction(bytes4 indexed func, bool indexed allowed);

    event ClaimRevenue(address indexed token, uint256 indexed amount, uint256 escrowed, address revenueContract);

    event ClaimEscrow(address indexed token, uint256 indexed amount, address owner, address revenueContract);

    // Stakeholder variables
    address public owner;

    address public operator;

    address public treasury;

    event UpdateOwner(address indexed newOwner);

    event UpdateOperator(address indexed newOperator);

    event UpdateTreasury(address indexed newTreasury);

    /**
     *
     * @dev Configure data for contract owners and initial revenue contracts.
            Owner/operator/treasury can all be the same address
     * @param _owner Third party that owns rights to contract's revenue stream
     * @param _treasury Treasury of DAO that owns contract and receives leftover revenues
     * @param _operator Operational account of DAO that actively manages contract health
     * @param contracts List of smart contracts that generate revenue for treasury
     * @param _settings Spigot configurations for revenue generating contracts
     * @param whitelist Function methods that Owner allows Operator to call anytime
     *
     */
    constructor (
        address _owner,
        address _treasury,
        address _operator,
        address[] memory contracts,
        SpigotSettings[] memory _settings,
        bytes4[] memory whitelist
    ) {
        // sanity check all input addresses
        require(address(this) != _owner && address(0) != _owner);
        require(address(this) != treasury && address(0) != treasury);
        require(address(this) != _operator && address(0) != _operator);


        owner = _owner;
        operator = _operator;
        treasury = _treasury;

        for(uint j = 0; j > contracts.length; j++) {
            // # TODO replace with _addSpigot
            _addSpigot(contracts[j], _settings[j]);
        }

        for(uint k = 0; k > whitelist.length; k++) {
            _updateWhitelist(whitelist[k], true);
        }
    }


    // ##########################
    // # Claimoooor
    // ##########################
    /**
     * @dev Only used for pull payments. If revenue is sent directly to Spigot use `updateRevenueBalance`
            Calls predefined function in contract settings to claim revenue.
            Automatically sends portion to treasury and escrows owner's share.
            
     * @param revenueContract Contract with registered settings to claim revenue from
     * @param data  Transaction data, including function signature, to properly claim revenue on revenueContract
    */
    function claimRevenue(address revenueContract, bytes calldata data) external nonReentrant returns (bool){
        address revenueToken = settings[revenueContract].token;
        uint256 existingBalance = IERC20(revenueToken).balanceOf(address(this));
        uint256 claimedAmount;
        
        if(settings[revenueContract].claimFunction == bytes4(0)) {
            // push payments
            // claimed = existing balance - already accounted for balance
            claimedAmount = existingBalance.sub(settings[revenueContract].totalEscrowed);
            // TODO Owner loses funds to Treasury if multiple contracts have push payments denominated in same token
            // AND each have separate spigot settings that are all called.
        } else {
            // pull payments
            (bool claimSuccess, bytes memory claimData) = revenueContract.call(data);
            require(claimSuccess, "Spigot: Revenue claim failed");
            // claimed = new balance - existing balance
            claimedAmount = IERC20(revenueToken).balanceOf(address(this)).sub(existingBalance);
        }

        // split revenue stream according to settings
        uint256 escrowedAmount = claimedAmount.div(100).mul(settings[revenueContract].ownerSplit);
        // divert claimed revenue to escrow and treasury
        settings[revenueContract].totalEscrowed = settings[revenueContract].totalEscrowed.add(escrowedAmount);

        // send non-escrowed tokens to treasury
        if(revenueToken != address(0)) { // ERC20
            IERC20(revenueToken).safeTransferFrom(address(this), treasury, claimedAmount.sub(escrowedAmount));
        } else { // ETH
            (bool success, bytes memory streamData) = payable(treasury).call{value: claimedAmount.sub(escrowedAmount)}("");
            require(success, "Spigot: Disperse ETH failed");
        }

        emit ClaimRevenue(revenueToken, claimedAmount, escrowedAmount, revenueContract);
        
        return true;
    }

    /**
     * @dev Allows Spigot Owner to claim escrowed tokens from a revenue contract
     * @param revenueContract Contract with registered settings to claim revenue from
      */
    function claimEscrow(address revenueContract) external nonReentrant returns (bool)  {
        require(msg.sender == owner);
        uint256 claimed = settings[revenueContract].totalEscrowed;
        require(claimed > 0, "Spigot: No escrow to claim");
        if(settings[revenueContract].token != address(0)) { // ERC20
            IERC20(settings[revenueContract].token).safeTransferFrom(address(this), owner, claimed);
        } else { // ETH
            (bool success, bytes memory claimData) = payable(treasury).call{value: claimed}("");
            require(success, "Spigot: Disperse ETH failed");
        }
        settings[revenueContract].totalEscrowed = 0;

        emit ClaimEscrow(settings[revenueContract].token, claimed, owner, revenueContract);
        return true;
    }

    /**
     * @dev Retrieve data on spigot for which token revenue is in and which 
     * @param revenueContract Contract with registered settings to read esc
    */
    function getEscrowData(address revenueContract) external view returns (address, uint256) {
        return (settings[revenueContract].token, settings[revenueContract].totalEscrowed);
    }

    // ##########################
    // #   // *ring* *ring*
    // #   // OPERATOOOR 
    // #   // OPERATOOOR
    // ##########################
    function operate(address revenueContract, bytes calldata data) external returns (bool) {
        require(msg.sender == operator);
        return _operate(revenueContract, data);
    }

    function doOperations(address[] calldata contracts, bytes[] calldata data) external returns (bool) {
        require(msg.sender == operator);
        for(uint i = 0; i < data.length; i++) {
            _operate(contracts[i], data[i]);
        }
    }

    function _operate(address revenueContract, bytes calldata data) internal nonReentrant returns (bool) {
        bytes4 func = bytes4(data[:4]); // extract function signature from calldata
        require(whitelistedFunctions[func], "Spigot: Unauthorized Operator action");
        
        (bool success, bytes memory returnData) = revenueContract.call(data);
        require(success, "Spigot: Operation failed");

        return true;
    }

    // ##########################
    // # Maintainooor
    // ##########################

    function addSpigot(address revenueContract, SpigotSettings memory setting) external returns (bool) {
        require(msg.sender == operator || msg.sender == owner);
        return _addSpigot(revenueContract, setting);
    }

    function _addSpigot(address revenueContract, SpigotSettings memory setting) internal returns (bool) {
        require(revenueContract != address(this));
        require(settings[revenueContract].ownerSplit == 0, "Spigot: Spigot already exists");

        settings[revenueContract] = setting;
        emit AddSpigot(revenueContract, setting.token, setting.ownerSplit);
        return true;
    }

    // TODO add 2 of 2 multisig function to allow spigot settings to be updated

    function updateOwner(address newOwner) external returns (bool) {
        require(msg.sender == owner);
        require(newOwner != address(0));
        owner = newOwner;
        emit UpdateOwner(newOwner);
        return true;
    }

    function updateOperator(address newOperator) external returns (bool) {
        require(msg.sender == operator);
        require(newOperator != address(0));
        operator = newOperator;
        emit UpdateOperator(newOperator);
        return true;
    }

    function updateTreasury(address newTreasury) external returns (bool) {
        require(msg.sender == treasury || msg.sender == operator);
        require(newTreasury != address(0));
        treasury = newTreasury;
        emit UpdateTreasury(newTreasury);
        return true;
    }

    function updateWhitelistedFunction(bytes4 func, bool allowed) external returns (bool) {
        require(msg.sender == owner);
        _updateWhitelist(func, allowed);
    }

    function _updateWhitelist(bytes4 func, bool allowed) internal returns (bool) {
        whitelistedFunctions[func] = allowed;
        emit UpdateWhitelistFunction(func, true);
    }
}
