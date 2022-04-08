pragma solidity 0.8.9;

interface IOracle {
    /** current price for token asset. denominated in USD + 18 decimals */
    function getLatestAnswer(address token) external returns(uint256);
}
