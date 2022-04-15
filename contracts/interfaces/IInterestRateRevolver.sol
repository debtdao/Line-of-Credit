pragma solidity ^0.8.9;

interface IInterestRateRevolver {
  function accrueInterest(
    uint256 drawnAmount,
    uint256 facilityAmount
  ) external view returns(uint256 repayBalance);
}
