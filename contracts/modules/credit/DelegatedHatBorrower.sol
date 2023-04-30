pragma solidity 0.8.16;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {CreditLib} from "../../utils/CreditLib.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";
import {IHats} from "../../interfaces/IHats.sol";

/**
    @title  DelegatedHatBorrower
    @author Kiba Gateaux
    @notice Allows a DAO to delegate ability to borrow from its credit facility.
            Uses Hats Protocol to manage access controls
            Manages its own financial credit limts *per hat*
            Hats Protocol settings e.g. eligibility, transferability are handled by admin externally
 */
contract DelegatedHatBorrower {
    using SafeERC20 for IERC20;
    event DelegatedBorrow(uint256 indexed hat, address indexed to, address indexed line, uint256 amount, address caller);

    struct CreditLimit {
        // amount of tokens that can be borrweed per epoch
        // MAX_UIINT for unlimited token borrowing, but can limit to epoch time
        // uint128 because unlikely entire credit line will be used by one hat
        uint128 limit;
        // can be 0 for one time use (even if infinite epochLength)
        // decrements after each epoch ends to 0.
        uint8 epochsLeft;
        // MAX_UINT for forever
        uint32 epochLength;
        // timestamp when last epoch was initiatied
        uint32 lastEpochStart;
    }

    IHats private constant hats = IHats(address(0)); // TODO get singleton deploymet address
    // hat that controls credit facility and 
    uint256 public immutable adminHat;

    // hat -> token -> amount withdrawable
    mapping(uint256 => mapping(address => CreditLimit)) hatCredits;
    
    constructor(uint256 _ownerHat) {
        adminHat = _ownerHat;
        // should we ensure that adminHat is above borrowerHat in hats tree hierarchy? seems like unnecessary restriction but reduces user fuckups
    }

    function _onlyOwner(address caller) internal view {
        require(hats.isWearerOfHat(caller, adminHat));
    }

    function setCreditLimit(uint256 hat, address token, uint128 amount, uint32 epochLength, uint8 totalEpochs) external returns(bool) {
        _onlyOwner(msg.sender);
        
        _setCreditLimit(hat, token, amount, epochLength, totalEpochs);

        return true;
    }

    function borrow(address line, uint256 hat, address token, uint128 amount, address _to) public returns(bool) {
        // check caller is even wearing hat before we check hat's credit limit
        require(hats.isWearerOfHat(msg.sender, hat));
        // check hats assigned limits by admin
        _assertCreditLimit(hat, token, amount);
        // update hat settings pre-reentrancy settings
        _reduceCreditLimit(hat, token, amount);

        // manually compute positionId to ensure righttoken is being borrowed for hat credit line
        ILineOfCredit(line).borrow(CreditLib.computeId(line, address(this), token), amount);
        // transfer token out to where hat wearer requested
        IERC20(token).transfer(_to, amount);

        emit DelegatedBorrow(hat, _to, line, amount, msg.sender);
        
        return true;
    }


    function _reduceCreditLimit(uint256 hat, address token, uint128 amount) internal returns(bool) {
        hatCredits[hat][token].limit -= amount;
        // emit event
        return true;
    }

    function _setCreditLimit(uint256 hat, address token, uint128 amount, uint32 epochLength, uint8 totalEpochs) internal returns(bool) {
        hatCredits[hat][token] = CreditLimit({
            lastEpochStart: uint32(block.timestamp),
            limit: amount,
            epochsLeft: totalEpochs,
            epochLength: epochLength
        });
        // emit event
        return true;
    }

    function _assertCreditLimit(uint256 hat, address token, uint128 amount) internal {
        CreditLimit memory setting = hatCredits[hat][token];
        
        if(setting.limit != type(uint32).max) {
            // if not infinite approval then must be within limit
            require(amount <= setting.limit);
        }

        // must be within epoch if not infinite time approval 
        uint32 nextEpochStart = setting.epochLength == type(uint32).max
            ? 0
            : setting.lastEpochStart + setting.epochLength;

        // if non-0 and epch has ended then reset epoch time and decrement epochs left
        bool resetEpoch = setting.epochsLeft != 0 && nextEpochStart != 0;

        if(resetEpoch) {
            require(setting.epochsLeft > 0);
            // next epoch always set based on CreditLimit state, not current time when updated
            // if overwriting with 0 on infinite approval theres no storage costs bc no state change
            setting.lastEpochStart = nextEpochStart;
            setting.epochsLeft -= 1;

            // save updated settings to storage!
            hatCredits[hat][token] = setting;
        }
    }

    /**
    * @notice Accepts/Proposes a single lending offer on a SecuredLine contract
    * @param line address of SecuredLine contract
    * @param drate fixed APR interest rate on undrawn capital
    * @param frate fixed APR interest rate on drawn capital
    * @param amount amount of tokens to borrow
    * @param lender address of lender
    * @param token address of token to borrow
    * @return id of lender's position on credit line
    */
    function addCredit(address line, uint128 drate, uint128 frate, uint256 amount, address lender, address token) external returns(bytes32) {
        _onlyOwner(msg.sender);
        
        require(address(this) == ILineOfCredit(line).borrower());
        
        return ILineOfCredit(line).addCredit(drate, frate, amount, lender, token);
    }


    function close(address line, bytes32 id) external returns(bool) {
        _onlyOwner(msg.sender);
        
        ILineOfCredit(line).close(id);

        return true;
    }

    function depositAndClose(address line, address token) external returns(bool) {
        _onlyOwner(msg.sender); // should we let any hat wearer with an active credit line in that token be able to close positions in that token?
        // potentially creates inter-org griefing if people close each others lines.
        
        IERC20(token).safeApprove(line, type(uint256).max);
        ILineOfCredit(line).depositAndClose();

        return true;
    }
}