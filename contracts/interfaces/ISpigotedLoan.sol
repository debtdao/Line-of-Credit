pragma solidity ^0.8.9;
interface ISpigotedLoan {
  event RevenuePayment(
    address indexed revToken,
    uint256 indexed revValue
  );

  function claimSpigotAndRepay(
    bytes32 positionId,
    address token,
    bytes calldata zeroExTradeData
  ) external returns(bool);
}
