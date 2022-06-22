import { LoanLib } from "../utils/LoanLib.sol";

interface ILoan {

  event DeployLoan(
    address indexed oracle,
    address indexed arbiter,
    address indexed borrower
  );

  event AddDebtPosition(
    address indexed lender,
    address indexed token,
    uint256 indexed deposit,
    uint256 initialPrincipal
  );

  // can reference only positionId once AddDebtPosition is emitted because it will be stored in subgraph
  // initialPrinicipal tells us if its a Revolver or Term

  event Withdraw(bytes32 indexed positionId, uint256 indexed amount);
  // lender removing funds from Loan (interest or principal)

  event CloseDebtPosition(bytes32 indexed positionId);
  // lender officially repaid in full. if Credit then facility has also been closed.

  event InterestAccrued(bytes32 indexed positionId, uint256 indexed tokenAmount, uint256 indexed value);
  // initerest added to borrowers outstanding balance

  // Borrower Events
  event Borrow(bytes32 indexed positionId, uint256 indexed amount, uint256 indexed value);
  // receive full loan or drawdown on credit

  event RepayInterest(bytes32 indexed positionId, uint256 indexed amount, uint256 indexed value);

  event RepayPrincipal(bytes32 indexed positionId, uint256 indexed amount, uint256 indexed value);

  event Liquidate(bytes32 indexed positionId, uint256 indexed amount, address indexed token);

  event Default(bytes32 indexed positionId);

  // General Events
  event UpdateLoanStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph


  // External Functions  
  function withdraw(bytes32 positionId, uint256 amount) external returns(bool);
  function liquidate(bytes32 positionId, uint256 amount, address targetToken) external returns(uint256);

  function depositAndRepay(uint256 amount) external returns(bool);
  function depositAndClose() external returns(bool);

  function accrueInterest() external returns(uint256 amountAccrued);
  function getOutstandingDebt() external returns(uint256 totalDebt);
  function healthcheck() external returns(LoanLib.STATUS);
}
