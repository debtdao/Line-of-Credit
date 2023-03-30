pragma solidity 0.8.16;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {CreditLib} from "../../utils/CreditLib.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";
import {IHats} from "../../interfaces/IHats.sol";

/**
    @notice Allows a DAO to delegate ability to borrow from its credit facility.
            Uses Hats Protocol to manage access controls
            Manages its own financial credit limts per member
 */
contract DelegatedHatBorrower {
    using SafeERC20 for IERC20;

    IHats private constant hats = IHats(address(0));
    // hat that controls credit facility and 
    uint256 public immutable ownerHat;
    uint256 public immutable borrowerHat;

    // borrower -> token -> amount withdrawable
    mapping(address => mapping(address => uint256)) borrowable;
    
    constructor(uint256 _ownerHat, uint256 _borrowerHat) {
        ownerHat = _ownerHat;
        borrowerHat = _borrowerHat;
        // should we ensure that ownerHat is above borrowerHat in hats tree hierarchy? seems like unnecessary restriction but reduces user fuckups
    }

    function _onlyOwner(address caller) internal view {
        require(hats.isWearerOfHat(caller, ownerHat));
    }

    function setCreditLimit(address borrower, address token, uint256 amount) external returns(bool) {
        _onlyOwner(msg.sender);
        
        _setCreditLimit(borrower, token, amount);

        return true;
    }

    function _borrow(address line, address borrower, address token, uint256 amount) internal {
        require(amount != 0);
        // ensure they still have authorization even if credit limit is non-zero
        require(hats.isWearerOfHat(borrower, borrowerHat));
        
        _setCreditLimit(borrower, token, borrowable[borrower][token] - amount);
        // underflow revert ensures they are within limit

        ILineOfCredit(line).borrow(CreditLib.computeId(line, borrower, token), amount);

        IERC20(token).transfer(borrower, amount);
    }

    function _setCreditLimit(address borrower, address token, uint256 amount) internal returns(bool) {
        borrowable[borrower][token] = amount;
        // emit event
        return true;
    }


    function addCredit(address line, uint128 drate, uint128 frate, uint256 amount, address lender, address token) external returns(bool) {
        _onlyOwner(msg.sender);
        
        require(address(this) == ILineOfCredit(line).borrower());
        
        ILineOfCredit(line).addCredit(drate, frate, amount, lender, token);

        return true;
    }

    function repay(address line, uint256 amount) external returns(bool) {
        _onlyOwner(msg.sender);
        (/* bytes32 id */, /* address lender */, address token, uint256 principal, uint256 interest, /* uint256 deposit */, /* uint128 drate */, /* uint128 frate */) = ILineOfCredit(line).nextInQ();
        
        if(amount == 0) {
            IERC20(token).approve(line, principal + interest);
            ILineOfCredit(line).depositAndClose();
        } else {
            IERC20(token).approve(line, amount);
            ILineOfCredit(line).depositAndRepay(amount);
        }

        return true;
    }

    function close(address line, bytes32 id) external returns(bool) {
        _onlyOwner(msg.sender);
        
        ILineOfCredit(line).close(id);

        return true;
    }


}