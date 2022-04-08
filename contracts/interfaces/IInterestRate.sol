import { LoanLib } from "../utils/LoanLib.sol";
import { IModule } from "./IModule.sol";

interface IInterestRate is IModule {
  function accrueInterest(
    bytes32 positionId, 
    uint256 amount, 
    LoanLib.STATUS currentStatus
  ) external returns(uint256);

  function healthcheck() external returns (LoanLib.STATUS status);
}
