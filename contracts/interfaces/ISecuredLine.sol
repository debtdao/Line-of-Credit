pragma solidity 0.8.9;

interface ISecuredLine {
  // Rollover
  error DebtOwed();
  error BadNewLine();
  error BadRollover();

  // Borrower functions
  function rollover(address newLine) external returns(bool);
}
