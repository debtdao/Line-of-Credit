import { LoanLib } from "../lib/LoanLib.sol";
import { IModule } from "./IModule.sol";

interface ISpigotConsumer {

  function transferSpigotOwner(address newOwner) external returns(bool);

  function updateRevenueSplit(address revenueContract, uint8 newSplit) external returns(bool);
  
  function claimAndTrade(
    address claimToken, 
    address targetToken,
    bytes calldata zeroExTradeData
  ) external returns(uint256 tokensBought);

  function claimTokens(address token) external returns(uint256);

  function getTotalTradableTokens(address token) external returns(uint256);

  function stream(address lender, address token, uint256 amount) external returns(bool);
}
