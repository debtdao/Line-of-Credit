pragma solidity ^0.8.9;

import { IInterestRateRevolver } from "../../interfaces/IInterestRateRevolver.sol";

contract InterestRateRevolver is IInterestRateRevolver {

    ///////////  CONSTANTS  ///////////
    uint256 constant RATE_DENOMINATOR = 10000;

    ///////////  VARIABLES  ///////////
    uint256 public lastPayment; // timestamp in unix
    uint256 public paymentInterval; // timestamp in unix
    uint256 public drawnRate; // in bps
    uint256 public facilityRate; // in bps
    address loanContract;
    
    
    ///////////  CONSTRUCTOR  ///////////

    /**
    * @dev Interest contract for the revolver loan
    * @param _paymentInterval how frequently interest payments are to be made
    * @param _drawnRate interest rate for drawn money
    * @param _facilityRate interest rate for money sitting in facility
     */
    constructor (
        uint256 _paymentInterval,
        uint256 _drawnRate,
        uint256 _facilityRate,
    ) {
        loanContract = msg.sender;
        paymentInterval = _paymentInterval;
        drawnRate = _drawnRate;
        facilityRate = _facilityRate;
        lastPayment = block.timestamp;
    }

    ///////////  MODIFIERS  ///////////

    modifier onlyLoanContract () {
        require(msg.sender == loanContract, "InterestRateRevolver::Must be called by loan contract.");
        _;
    }

    ///////////  FUNCTIONS  ///////////

    /**
    * @dev accrueInterest function for term loan
    * @param drawnBalance balance of drawn funds
    * @param facilityBalance balance of facility funds
    * @return repayBalance amount to be repaid for this interest period
    * @return missedPayment whether the borrower has missed this past interest period
    *  */
    function accrueInterest(uint256 drawnBalance, uint256 facilityBalance) external view override returns (uint256 repayBalance, bool missedPayment) {
        // calculate interest for payment period
        repayBalance = 
        drawnBalance * (drawnRate / RATE_DENOMINATOR) + 
        facilityBalance * (facilityRate / RATE_DENOMINATOR);

        // check if missed payment using timestamp
        missedPayment = 
        (block.timestamp - lastPayment >= paymentInterval) ? 
        true : 
        false;
    }

    /** 
    * @dev change rate
    * @param newDrawn new drawn rate 
    * @param newFacility new facility rate
     */
    function changeRates(uint256 newDrawn, uint256 newFacility) external onlyLoanContract {
        drawnRate = newDrawn;
        facilityRate = newFacility;
    }
}