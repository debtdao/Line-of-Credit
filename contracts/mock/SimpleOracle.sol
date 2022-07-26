pragma solidity 0.8.9;

import { IOracle } from "../interfaces/IOracle.sol";
import { LoanLib } from "../utils/LoanLib.sol";

contract SimpleOracle is IOracle {

    mapping(address => int) prices;

    constructor(address _supportedToken1, address _supportedToken2) {
        prices[_supportedToken1] = 1000 * 1e8; // 1000 USD
        prices[_supportedToken2] = 2000 * 1e8; // 2000 USD
    }

    function init() external returns(bool) {
        return true;
    }

    function changePrice(address token, int newPrice) external {
        prices[token] = newPrice;
    }

    function getLatestAnswer(address token) external returns(int256) {
        // mimic eip4626
        // (bool success, bytes memory result) = token.call(abi.encodeWithSignature("asset()"));
        // if(success && result.length > 0) {
        //     // get the underlying token value (if ERC4626)
        //     // NB: Share token to underlying ratio might not be 1:1
        //     token = abi.decode(result, (address));
        // }
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
