library LoanLib {
    address constant DEBT_TOKEN = address(0xdebf);
  
    enum STATUS {
    // ¿hoo dis
    // Loan has been deployed but terms and conditions are still being signed off by parties
    UNINITIALIZED, // [#X]
    INITIALIZED, // [#X] 

    // ITS ALLLIIIIVVEEE
    // Loan is operational and actively monitoring status
    ACTIVE, // [#X] 
    UNDERCOLLATERALIZED, // [#X]
    LIQUIDATABLE, // [#X
    DELINQUENT, // [#X]

    // Loan is in distress and paused
    LIQUIDATING, // [#X]
    OVERDRAWN, // [#X]
    DEFAULT, // [#X]
    ARBITRATION, // [#X]

    // Lön izz ded
    // Loan is no longer active, successfully repaid or insolvent
    REPAID, // [#X]
    INSOLVENT // [#X]
  }

}
