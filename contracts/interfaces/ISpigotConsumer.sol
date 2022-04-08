import { LoanLib } from "../utils/LoanLib.sol";

interface ISpigotConsumer {
  
  function claimAndTrade(
    address claimToken, 
    address targetToken,
    bytes calldata zeroExTradeData
  ) external returns(uint256 tokensBought);
  function stream(address lender, address token, uint256 amount) external returns(bool);
}
