import { IModule } from "./IModule.sol";
import { IModule } from "./IModule.sol";
import { LoanLib } from "../lib/LoanLib.sol";
interface ILoan is IModule {
  
  function addDebtPosition(uint256 amount, address token, address lender) external returns(bool);
  function withdraw(uint256 positionId, uint256 amount) external returns(bool);
  function borrow(uint256 positionId, uint256 amount) external returns(bool);
  function close(uint256 positionId) external returns(bool);


  function depositAndRepay(uint256 positionId, uint256 amount) external returns(bool);
  function depositAndClose(uint256 positionId) external returns(bool);
  function claimSpigotAndRepay(
    uint256 positionId,
    address token,
    bytes[] calldata zeroExTradeData
  ) external returns(bool);
  
  // function depositAndRepay(uint256 positionId, uint256 amount) external returns(bool);

  function accrueInterest() external returns(uint256 amountAccrued);
  // function liquidate() external returns(uint256 totalValueLiquidated);
}
