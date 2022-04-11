interface ITermLoan {
  event RepayOverdue(bytes32 indexed positionId, uint256 indexed amount);
}
