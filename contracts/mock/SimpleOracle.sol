pragma solidity 0.8.9;

import { IOracle } from "../interfaces/IOracle.sol";
import { LoanLib } from "../lib/LoanLib.sol";

contract SimpleOracle is IOracle {

    address supportedToken;
    uint price;

    constructor(address _supportedToken) {
        supportedToken = _supportedToken;
        price  = 1000;
    }

    function changePrice(uint newPrice) external {
        price = newPrice;
    }

    function getLatestAnswer(address token) external returns(uint256) {
        require(token == supportedToken, "SimpleOracle: unsupported token");
        return price;
    }

    function healthcheck() external returns (LoanLib.STATUS status) {
        return LoanLib.STATUS.ACTIVE;
    }

    function loan() external returns (address) {
        return address(0);
    }

}
