import { LoanLib } from "../lib/LoanLib.sol";
import { IModule } from "./IModule.sol";

interface IInterestRate is IModule {
  function accrueInterest(
    uint256 lenderId, 
    uint256 amount, 
    LoanLib.STATUS currentStatus
  ) external returns(uint256);

  function healthcheck() external returns (LoanLib.STATUS status);
}
