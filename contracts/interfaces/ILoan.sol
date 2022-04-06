import { IModule } from "./IModule.sol";
import { IModule } from "./IModule.sol";
import { LoanLib } from "../utils/LoanLib.sol";

interface ILoan {
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

  event Liquidated(bytes32 indexed positionId, uint256 indexed amount, address indexed token);

  // General Events
  event UpdateLoanStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph


  // External Functions  
  function addDebtPosition(uint256 amount, address token, address lender) external returns(bool);
  function withdraw(bytes32 positionId, uint256 amount) external returns(bool);
  function borrow(bytes32 positionId, uint256 amount) external returns(bool);
  function close(bytes32 positionId) external returns(bool);
  function emergencyClose(bytes32 positionId) external returns(bool);

  function depositAndRepay(bytes32 positionId, uint256 amount) external returns(bool);
  function depositAndClose(bytes32 positionId) external returns(bool);
  function claimSpigotAndRepay(
    bytes32 positionId,
    address token,
    bytes calldata zeroExTradeData
  ) external returns(bool);

  function accrueInterest() external returns(uint256 amountAccrued);
  function getOutstandingDebt() external returns(uint256 totalDebt);
  // function liquidate() external returns(uint256 totalValueLiquidated);
}
