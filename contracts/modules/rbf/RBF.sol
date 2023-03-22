pragma solidity 0.8.16;

import {ISpigot} from "../../interfaces/ISpigot.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {MutualConsent} from "../../utils/MutualConsent.sol";

/**
 * @notice - Contract that allows buying a fixed % of total revenue from a Spigot for a fixed amount of time
 *           This contract is owner of Spigot so ownerSplit is what rev share they are buying as `rev_recipient`
 *           The `owner` ofthis contracts is liekly the `operator` on the Spigot who acts on behalf of OG rev owner
 *
  * Can either do discrete mutualConsent for fixded % + time sales or do continous harberger tax with lower bounds set by owner
 *
 *
 *
  *
 *
 *
 *
  *
 *
 *
 *
  *
 *
 *
 *  */
contract RBF is MutualConsent {
    
    using SafeERC20 for IERC20;

    ISpigot immutable spigot;
    address rev_recipient;
    address owner;
    uint8 targetSplit;
    uint256 endTime;
    
    constructor(address _owner, address _spigot) {
        spigot = ISpigot(_spigot);
        rev_recipient = _owner;
        targetSplit = 0; // operator gets all tokens until someone buys rights from them
    }


// this contract is the Owner of spigot alwayts, operator will remain operator. 
// This contract defaults to operator as rev_recipient unless someone is paying to be the rev_recipient


// harberger rbf - ttl >= curr_ttl or split <= curr_split

    function sellRevShares(
        address buyer,
        address token,
        uint256 amount,
        uint256 ttl,
        uint8 ownerSplit,
    ) mutualConsent(owner, buyer) external returns(bool) {
        require(endTime < block.timestamp); // currently active
        endTime = block.timestamp + ttl,
        rev_recipient = buyer
        IERC20(token).transferFrom(buyer, owner, amount);
        return true;
    }

    function sellRevContract(
        address buyer,
        address token,
        uint256 amount,
        address revContract,
    ) mutualConsent(owner, buyer)  external returns(bool) {
        require(block.timestamp < agreement.endTime); // cant sell contracts will revshare is active
        IERC20(token).transferFrom(buyer, owner, amount);
        spigot.releaseSpigot(revContract, buyer);
    }

    function updateOwnerSplit(address revContract) external returns(bool) {
        require(block.timestamp < agreement.endTime);
        return spigot.updateOwnerSplit(revContract, agreement.ownerSplit);
    }

    function addSpigot(address revContract) external returns(bool) {
        require(block.timestamp < agreement.endTime);
        return spigot.updateOwnerSplit(revContract, agreement.ownerSplit);
    }

    function claim_rev(address token, address to) external returns(bool) {
        require(msg.sender == rev_recipient);
        require(block.timestamp < agreement.endTime);

        uint256 amount = spigot.claimOwnerTokens(token);
        IERC20(token).transfer(rev_recipient, amount);
        return true;
    }

    //  we can to rev share per contract bc we agregate tokens  in spigot across rev contracts
    // function share(
    //     address revContract,
    //     address lender,
    //     address token,
    //     uint256 amount,
    //     uint256 ttl,
    //     uint8 ownerSplit,
        // address[] revContracts

    // ) mutualConsent(rev_recipient, lender) external returns(bool) {
    //     require(revShares[revContract].endTime == 0); // already exists


        // should be here for security reasons but feels simpler to have them batch call later
        //  spigot.claimOwnerTokens(token);
        // uint256 length = revContracts.length
        // for(uint256 i; i < length;) {
        //     spigot.updateOwnerSplit(revContract, agreement.ownerSplit);
        //     unchecked { ++i }
        // }

    //     spigot.updateOwnerSplit(revContract, ownerSplit);
    //     IERC20(token).transferFrom(lender, address(this), amount);

    //     return true;
    // }




}