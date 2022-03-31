/**
* Standard oracle contract to pull from Chainlink registry
 */

interface IOracle {
  /** current price for token asset. denominated in USD + 18 decimals */
  function getLatestAnswer(address token) external returns(int);
}
