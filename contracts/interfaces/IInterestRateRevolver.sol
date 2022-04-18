pragma solidity ^0.8.9;

interface IInterestRateRevolver {
  function accrueInterest(
    uint256 drawnAmount,
    uint256 facilityAmount
  ) external returns(uint256 repayBalance);

  function changeRates(uint256 _drawnRate, uint256 _facilityRate) external;
}
