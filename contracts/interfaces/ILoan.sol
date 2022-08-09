pragma solidity 0.8.9;

import { LoanLib } from "../utils/LoanLib.sol";
import { IOracle } from "../interfaces/IOracle.sol";

interface ILoan {

  // General Events
  event UpdateLoanStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph

  event DeployLoan(
    address indexed oracle,
    address indexed arbiter,
    address indexed borrower
  );

  // Lender Events

  event AddCredit(
    address indexed lender,
    address indexed token,
    uint256 indexed deposit,
    bytes32 positionId
  );

   event IncreaseCredit (
    bytes32 indexed id,
    uint256 indexed deposit
  );

  // can reference only id once AddCredit is emitted because it will be stored in subgraph
  // initialPrinicipal tells us if its a Revolver or Term

  event WithdrawDeposit(bytes32 indexed id, uint256 indexed amount);
  // lender removing funds from Loan  principal
  event WithdrawProfit(bytes32 indexed id, uint256 indexed amount);
  // lender taking interest earned out of contract

  event CloseCreditPosition(bytes32 indexed id);
  // lender officially repaid in full. if Credit then facility has also been closed.

  event InterestAccrued(bytes32 indexed id, uint256 indexed amount);
  // interest added to borrowers outstanding balance


  // Borrower Events

  event Borrow(bytes32 indexed id, uint256 indexed amount);
  // receive full loan or drawdown on credit

  event RepayInterest(bytes32 indexed id, uint256 indexed amount);

  event RepayPrincipal(bytes32 indexed id, uint256 indexed amount);

  event Default(bytes32 indexed id);

  // External Functions  
  function withdraw(bytes32 id, uint256 amount) external returns(bool);

  function depositAndRepay(uint256 amount) external returns(bool);
  function depositAndClose() external returns(bool);

  function accrueInterest() external returns(bool);
  function updateOutstandingDebt() external returns(uint256, uint256);
  function healthcheck() external returns(LoanLib.STATUS);

  function borrower() external returns(address);
  function arbiter() external returns(address);
  function loanStatus() external returns(LoanLib.STATUS);
  function oracle() external returns(IOracle);
}
