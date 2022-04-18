pragma solidity ^0.8.9;

import { IInterestRateRevolver } from "../../interfaces/IInterestRateRevolver.sol";


contract InterestRateRevolver is IInterestRateRevolver {

    ///////////  CONSTANTS  ///////////
    uint256 constant RATE_DENOMINATOR = 10000;

    ///////////  VARIABLES  ///////////
    uint256 public lastAccrual; // timestamp in unix
    uint256 public drawnRate; // in bps
    uint256 public facilityRate; // in bps
    address loanContract;
    
    ///////////  CONSTRUCTOR  ///////////

    /**
    * @dev Interest contract for the revolver loan
    * @param _drawnRate interest rate for drawn money
    * @param _facilityRate interest rate for money sitting in facility
     */
    constructor (
        uint256 _drawnRate,
        uint256 _facilityRate
    ) {
        loanContract = msg.sender;
        drawnRate = _drawnRate;
        facilityRate = _facilityRate;
    }

    ///////////  MODIFIERS  ///////////

    modifier onlyLoanContract () {
        require(msg.sender == loanContract, "InterestRateRevolver::Must be called by loan contract.");
        _;
    }

    ///////////  FUNCTIONS  ///////////

    /**
    * @dev accrueInterest function for revolver loan
    * @param drawnBalance balance of drawn funds
    * @param facilityBalance balance of facility funds
    * @return repayBalance amount to be repaid for this interest period
    *  */
    function accrueInterest(uint256 drawnBalance, uint256 facilityBalance) external override returns (uint256 repayBalance) {
        // reset last payment
        lastAccrual = block.timestamp;

        // calculate interest for payment period
        repayBalance = 
        drawnBalance * (drawnRate / RATE_DENOMINATOR) + 
        facilityBalance * (facilityRate / RATE_DENOMINATOR);

        
    }

    /** 
    * @dev change rate
    * @param _drawnRate new drawn rate
    * @param _facilityRate new facility rate
     */
    function changeRates(uint256 _drawnRate, uint256 _facilityRate) external override onlyLoanContract {
        drawnRate = _drawnRate;
        facilityRate = _facilityRate;
    }
}