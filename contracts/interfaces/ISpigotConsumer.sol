import { LoanLib } from "../utils/LoanLib.sol";

interface ISpigotConsumer {
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
}
