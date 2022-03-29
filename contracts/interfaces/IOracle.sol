import { LoanLib } from "../lib/LoanLib.sol";
import { IModule } from "./IModule.sol";

interface IOracle is IModule {
  /** current price for token asset. denominated in USD + 18 decimals */
  function getLatestAnswer(address token) external returns(uint256);

  function healthcheck() external returns (LoanLib.STATUS status);
}
