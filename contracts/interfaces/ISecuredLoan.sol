pragma solidity 0.8.9;

interface ISecuredLoan {
  // Rollover
  error DebtOwed();
  error BadNewLoan();

  // Borrower functions
  function rollover(address newLoan) external returns(bool);
}
