pragma solidity ^0.8.9;

import "../../interfaces/IInterestRate.sol";
import "../../lib/LoanLib.sol";

contract InterestRate is IInterestRate {
    
    ////////// CONSTANTS //////////

    uint constant DENOMINATOR = 10000;

    ////////// VARIABLES //////////

    uint256 timestamp; // timestamp to keep track of last time interest was paid
    mapping(uint256 => uint256) undrawnRates; // keeps track of undrawn rate for each positionId
    mapping(uint256 => uint256) drawnRates; // keeps track of drawn rate for each positionId

    // does each lender have a rate for the loan they give?

    // function to add a lender
    function addLenderRate(uint256 lenderId, uint256 interestRate) external {

    }
    
    // function to calculate and return amount of interest to be paid
    function calculateInterest(uint256 lenderId, uint256 dueDate, LoanLib.status loanStatus) external returns (uint256) {
        require(loanStatus != LoanLib.status.REPAID, "Loan is already repaid"); 

        // calculate interest rate using previous timestamp, interest rate, principal, and due-date of loan

        // set 

    }

    // 

}