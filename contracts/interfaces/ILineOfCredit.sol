pragma solidity 0.8.9;

import { LoanLib } from "../utils/LoanLib.sol";
import { ILoan } from "./ILoan.sol";
import { IOracle } from "../interfaces/IOracle.sol";

interface ILineOfCredit is ILoan {
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

  event SetRates(bytes32 indexed id, uint128 indexed drawnRate, uint128 indexed facilityRate);


  // Access Errors
  error NotActive();
  error NotBorrowing();
  error CallerAccessDenied();
  
  // Tokens
  error TokenTransferFailed();
  error NoTokenPrice();

  // Loan
  error BadModule(address module);
  error NoLiquidity(bytes32 position);
  error PositionExists();
  error CloseFailedWithPrincipal();

  function init() external returns(LoanLib.STATUS);

  function addCredit(
    uint128 drate,
    uint128 frate,
    uint256 amount,
    address token,
    address lender
  ) external returns(bytes32);

  function setRates(
    bytes32 id,
    uint128 drate,
    uint128 frate
  ) external returns(bool);

  function increaseCredit(bytes32 id, uint256 amount) external returns(bool);

  function borrow(bytes32 id, uint256 amount) external returns(bool);
  function depositAndRepay(uint256 amount) external returns(bool);
  function depositAndClose() external returns(bool);
  function close(bytes32 id) external returns(bool);

  function withdraw(bytes32 id, uint256 amount) external returns(bool);

  function accrueInterest() external returns(bool);
  function updateOutstandingDebt() external returns(uint256, uint256);
  function healthcheck() external returns(LoanLib.STATUS);

  function borrower() external returns(address);
  function arbiter() external returns(address);
  function oracle() external returns(IOracle);
}
