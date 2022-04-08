pragma solidity ^0.8.9;
interface ISpigotedLoan {
  function claimSpigotAndRepay(
    bytes32 positionId,
    address token,
    bytes calldata zeroExTradeData
  ) external returns(bool);
}
