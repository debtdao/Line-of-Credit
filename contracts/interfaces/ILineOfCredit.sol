pragma solidity 0.8.9;

import { LineLib } from "../utils/LineLib.sol";
import { IOracle } from "../interfaces/IOracle.sol";

interface ILineOfCredit {
  // Lender data
  struct Credit {
    //  all denominated in token, not USD
    uint256 deposit;          // total liquidity provided by lender for token
    uint256 principal;        // amount actively lent out
    uint256 interestAccrued;  // interest accrued but not repaid
    uint256 interestRepaid;   // interest repaid by borrower but not withdrawn by lender
    uint8 decimals;           // decimals of credit token for calcs
    address token;            // token being lent out
    address lender;           // person to repay
  }
  // General Events
  event UpdateStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph

  event DeployLine(
    address indexed oracle,
    address indexed arbiter,
    address indexed borrower
  );

  // MutualConsent borrower/lender events

  event AddCredit(
    address indexed lender,
    address indexed token,
    uint256 indexed deposit,
    bytes32 positionId
  );
  // can reference only id once AddCredit is emitted because it will be indexed offchain

  event SetRates(bytes32 indexed id, uint128 indexed drawnRate, uint128 indexed facilityRate);

  event IncreaseCredit (bytes32 indexed id, uint256 indexed deposit);

  // Lender Events

  event WithdrawDeposit(bytes32 indexed id, uint256 indexed amount);
  // lender removing funds from Line  principal
  event WithdrawProfit(bytes32 indexed id, uint256 indexed amount);
  // lender taking interest earned out of contract

  event CloseCreditPosition(bytes32 indexed id);
  // lender officially repaid in full. if Credit then facility has also been closed.

  event InterestAccrued(bytes32 indexed id, uint256 indexed amount);
  // interest added to borrowers outstanding balance


  // Borrower Events

  event Borrow(bytes32 indexed id, uint256 indexed amount);
  // receive full line or drawdown on credit

  event RepayInterest(bytes32 indexed id, uint256 indexed amount);

  event RepayPrincipal(bytes32 indexed id, uint256 indexed amount);

  event Default(bytes32 indexed id);

  // Access Errors
  error NotActive();
  error NotBorrowing();
  error CallerAccessDenied();
  
  // Tokens
  error TokenTransferFailed();
  error NoTokenPrice();

  // Line
  error BadModule(address module);
  error NoLiquidity();
  error PositionExists();
  error CloseFailedWithPrincipal();
  error NotInsolvent(address module);
  error NotLiquidatable();
  error AlreadyInitialized();

  function init() external returns(LineLib.STATUS);

  // MutualConsent functions
  function addCredit(
    uint128 drate,
    uint128 frate,
    uint256 amount,
    address token,
    address lender
  ) external payable returns(bytes32);
  function setRates(bytes32 id, uint128 drate, uint128 frate) external returns(bool);
  function increaseCredit(bytes32 id, uint256 amount) external payable returns(bool);

  // Borrower functions
  function borrow(bytes32 id, uint256 amount) external returns(bool);
  function depositAndRepay(uint256 amount) external payable returns(bool);
  function depositAndClose() external payable returns(bool);
  function close(bytes32 id) external payable returns(bool);
  
  // Lender functions
  function withdraw(bytes32 id, uint256 amount) external returns(bool);

  // Arbiter functions
  function declareInsolvent() external returns(bool);

  function accrueInterest() external returns(bool);
  function healthcheck() external returns(LineLib.STATUS);
  function updateOutstandingDebt() external returns(uint256, uint256);

  function status() external returns(LineLib.STATUS);
  function borrower() external returns(address);
  function arbiter() external returns(address);
  function oracle() external returns(IOracle);
  function counts() external view returns (uint256, uint256);
}
