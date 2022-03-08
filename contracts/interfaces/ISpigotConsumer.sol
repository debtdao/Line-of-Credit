import { LoanLib } from "../lib/LoanLib.sol";
import { IModule } from "./IModule.sol";

interface ISpigotConsumer is IModule {
  
  function claimAndTrade(
    address claimToken, 
    address targetToken,
    bytes[] calldata zeroExTradeData
  ) external returns(uint256 tokensBought);
  function stream(address lender, address token, uint256 amount) external returns(bool);

  function healthcheck() external returns (LoanLib.STATUS status);
}
