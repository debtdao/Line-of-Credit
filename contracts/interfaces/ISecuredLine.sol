pragma solidity 0.8.9;

interface ISecuredLine {
  // Rollover
  error DebtOwed();
  error BadNewLine();

  // Borrower functions
  function rollover(address newLine) external returns(bool);
}
