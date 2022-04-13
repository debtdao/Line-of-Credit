pragma solidity ^0.8.9;

interface IInterestRateTerm {
  function accrueInterest(
    uint256 amount 
  ) external view returns(uint256 repayBalance, bool missedPayment);
}
