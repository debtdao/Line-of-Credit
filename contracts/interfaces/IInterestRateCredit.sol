pragma solidity ^0.8.9;

interface IInterestRateCredit {
    struct Rate {
        // The interest rate charged to a Borrower on borrowed / drawn down funds
        // in bps, 4 decimals
        uint128 dRate;
        // The interest rate charged to a Borrower on the remaining funds available, but not yet drawn down (rate charged on the available headroom)
        // in bps, 4 decimals
        uint128 fRate;
        // The time stamp at which accrued interest was last calculated on an ID and then added to the overall interestAccrued (interest due but not yet repaid)
        uint256 lastAccrued;
    }

    function accrueInterest(bytes32 id, uint256 drawnAmount, uint256 facilityAmount) external returns (uint256);

    function setRate(bytes32 id, uint128 dRate, uint128 fRate) external returns (bool);
}
