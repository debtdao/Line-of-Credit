pragma solidity ^0.8.9;

import { IInterestRateTerm } from "../../interfaces/IInterestRateTerm.sol";

contract InterestRateTerm is IInterestRateTerm {

    ///////////  CONSTANTS  ///////////
    uint256 constant RATE_DENOMINATOR = 10000;

    ///////////  VARIABLES  ///////////
    uint256 public lastPayment; // timestamp in unix
    uint256 public interestRate; // in bps
    address loanContract;

    
    
    ///////////  CONSTRUCTOR  ///////////

    /**
    * @dev Interest contract for the term loan
    * @param _paymentInterval how frequently interest payments are to be made
    * @param _interestRate interest rate for loan
     */
    constructor (
        uint256 _paymentInterval,
        uint256 _interestRate
    ) {
        loanContract = msg.sender;
        paymentInterval = _paymentInterval;
        interestRate = _interestRate;
        lastPayment = block.timestamp;
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
    * @return missedPayment whether the borrower has missed this past interest period
    *  */
    function accrueInterest(uint256 balance) external view override returns (uint256 repayBalance) {
        // calculate interest for payment period
        repayBalance = balance * (interestRate / RATE_DENOMINATOR);

        // reset last payment
        lastPayment = block.timestamp;
    }

    /** 
    * @dev change rate
    * @param newRate rate of interest for undrawn component
     */
    function changeRate(uint256 newRate) external onlyLoanContract {
        interestRate = newRate;
    }
}