pragma solidity ^0.8.9;

interface IInterestRateCredit {
  struct Rate {
    // interest rate on amount currently being borrower
    uint128 drawnRate;
    // interest rate on amount deposited by lender but not currently being borrowed
    uint128 facilityRate;
    // timestamp that interest was last accrued on this position
    uint256 lastAccrued;
  }

  function accrueInterest(
    bytes32 positionId,
    uint256 drawnAmount,
    uint256 facilityAmount
  ) external view returns(uint256);

  function updateRate(
    bytes32 positionId,
    Rate calldata rate
  ) external returns(bool);
}
