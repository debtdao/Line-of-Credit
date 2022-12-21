pragma solidity 0.8.9;

import {Denominations} from "chainlink/Denominations.sol";

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {LineLib} from "../utils/LineLib.sol";

contract SimpleOracle is IOracle {
    mapping(address => int) prices;

    constructor(address _supportedToken1, address _supportedToken2) {
        prices[_supportedToken1] = 1000 * 1e8; // 1000 USD
        prices[_supportedToken2] = 2000 * 1e8; // 2000 USD
        prices[Denominations.ETH] = 2000 * 1e8; // 2000 USD
    }

    function init() external pure returns (bool) {
        return true;
    }

    function decimals(address token, address quote) external view returns (uint8) {
        return ERC20(token).decimals();
    }

    function changePrice(address token, int newPrice) external {
        prices[token] = newPrice;
    }

    function getLatestAnswer(address token) external view returns (int256) {
        require(prices[token] != 0, "SimpleOracle: unsupported token");
        return prices[token];
    }

    function healthcheck() external pure returns (LineLib.STATUS status) {
        return LineLib.STATUS.ACTIVE;
    }

    function line() external pure returns (address) {
        return address(0);
    }
}
