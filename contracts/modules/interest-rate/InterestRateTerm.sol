pragma solidity ^0.8.9;

import { IInterestRateTerm } from "../../interfaces/IInterestRateTerm.sol";

contract InterestRateTerm is IInterestRateTerm {

    ///////////  CONSTANTS  ///////////
    uint256 constant RATE_DENOMINATOR = 10000; // adding two zeroes to account for bps in numerator

    ///////////  VARIABLES  ///////////
    uint256 public immutable interestRate; // in bps (RIGHT NOW THIS EXPECTS THE RATE BY PERIOD, NOT APY)
    address loanContract;
    
    ///////////  CONSTRUCTOR  ///////////

    /**
    * @dev Interest contract for the term loan
    * @param _interestRate interest rate for loan
     */
    constructor (
        uint256 _interestRate
    ) {
        loanContract = msg.sender;
        interestRate = _interestRate;
    }

    ///////////  MODIFIERS  ///////////

    modifier onlyLoanContract () {
        require(msg.sender == loanContract, "InterestRateTerm::Must be called by loan contract.");
        _;
    }

    ///////////  FUNCTIONS  ///////////

    /**
    * @dev accrueInterest function for term loan
    * @param balance amount of balance in the loan contract 
    * @return repayBalance amount to be repaid for this interest period
    *  */
    function accrueInterest(uint256 balance) external view override returns (uint256 repayBalance) {
        // calculate interest for payment period
        repayBalance = balance * (interestRate / RATE_DENOMINATOR);
    }
}