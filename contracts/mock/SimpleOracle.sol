pragma solidity 0.8.9;

import { IOracle } from "../interfaces/IOracle.sol";
import { LoanLib } from "../lib/LoanLib.sol";

contract SimpleOracle is IOracle {

    mapping(address => uint) prices;

    constructor(address _supportedToken1, address _supportedToken2) {
        prices[_supportedToken1] = 1000;
        prices[_supportedToken2] = 1000;
    }

    function init() external returns(bool) {
        return true;
    }

    function changePrice(address token, uint newPrice) external {
        prices[token] = newPrice;
    }

    function getLatestAnswer(address token) external returns(uint256) {
        require(prices[token] != 0, "SimpleOracle: unsupported token");
        return prices[token];
    }

    function healthcheck() external returns (LoanLib.STATUS status) {
        return LoanLib.STATUS.ACTIVE;
    }

    function loan() external returns (address) {
        return address(0);
    }

}
