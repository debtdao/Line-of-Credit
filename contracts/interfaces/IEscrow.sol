import { LoanLib } from "../lib/LoanLib.sol";
import { IModule } from "./IModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEscrow is IModule {

  function healthcheck() external returns (LoanLib.STATUS status);
  function releaseCollateral(IERC20 token, uint256 _amount, address arbiter) external;
}
