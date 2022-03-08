import { LoanLib } from "../lib/LoanLib.sol";
import { IModule } from "./IModule.sol";

interface IEscrow is IModule {

  function healthcheck() external returns (LoanLib.STATUS status);
}
