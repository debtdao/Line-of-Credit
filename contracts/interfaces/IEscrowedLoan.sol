pragma solidity 0.8.9;

interface IEscrowedLoan {
  event Liquidate(bytes32 indexed positionId, uint256 indexed amount, address indexed token);

  function liquidate(uint256 amount, address targetToken) external returns(uint256);
}
