import { IModule } from "./IModule.sol";
import { IModule } from "./IModule.sol";
import { LoanLib } from "../lib/LoanLib.sol";
interface ILoan is IModule {
  // Stakeholder data
  struct DebtPosition {
    address lender;           // person to repay
    address token;            // token being lent out
    // all deonminated in token, not USD
    uint256 deposit;          // total liquidity provided by lender for token
    uint256 principal;        // amount actively lent out
    uint256 interestAccrued;  // interest accrued but not repaid
  }

  // Lender Events
  event Withdraw(address indexed lender, address indexed token, uint256 indexed amount);

  event AddDebtPosition(address indexed lender, address indexed token, uint256 indexed deposit);

  event CloseDebtPosition(address indexed lender, address indexed token);

  // Borrower Events
  event Borrow(address indexed lender, address indexed token, uint256 indexed amount);

  event Repay(address indexed lender, address indexed token, uint256 indexed amount);

  event Liquidated(uint256 indexed positionId, uint256 indexed amount, address indexed token);

  // General Events
  event UpdateLoanStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph


  // External Functions  
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

  function accrueInterest() external returns(uint256 amountAccrued);
  // function liquidate() external returns(uint256 totalValueLiquidated);
}
