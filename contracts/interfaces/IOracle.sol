pragma solidity 0.8.9;
import { IModule } from "./IModule.sol";

interface IOracle is IModule {
    /** current price for token asset. denominated in USD + 18 decimals */
    function getLatestAnswer(address token) external returns(uint256);
}