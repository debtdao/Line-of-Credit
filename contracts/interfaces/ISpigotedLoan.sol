pragma solidity ^0.8.9;
interface ISpigotedLoan {
  event RevenuePayment(
    address indexed token,
    uint256 indexed amount,
    uint256 indexed value
  );

  event TradeSpigotRevenue(
    address indexed revenueToken,
    uint256 revenueTokenAmount,
    address indexed debtToken,
    uint256 indexed debtTokensBought
  );

  function claimAndTrade(
    address claimToken, 
    address targetToken,
    bytes calldata zeroExTradeData
  ) external returns(uint256 tokensBought);

  function claimSpigotAndRepay(
    bytes32 positionId,
    address token,
    bytes calldata zeroExTradeData
  ) external returns(bool);
}
