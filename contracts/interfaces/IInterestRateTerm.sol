pragma solidity ^0.8.9;

interface IInterestRateTerm {
  function accrueInterest(
    uint256 amount 
  ) external returns(uint256 repayBalance);

  function changeRate(uint256 _interestRate) external;
}
