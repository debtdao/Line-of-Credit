import { IModule } from "./IModule.sol";
import { IModule } from "./IModule.sol";
import { LoanLib } from "../lib/LoanLib.sol";
interface ILoanBase is IModule {
  function accrueInterest() external returns(uint256 totalInterestAccrued);
  
  function depositAndRepay(uint256 positionId, uint256 amount) external returns(bool);
  function claimSpigotAndRepay(address token, bytes[] calldata zeroExTradeData) external returns(bool);
  // function depositAndRepay(uint256 positionId, uint256 amount) external returns(bool);

  function liquidate() external returns(uint256 totalValueLiquidated);


  function healthcheck() external returns(LoanLib.STATUS);
}
