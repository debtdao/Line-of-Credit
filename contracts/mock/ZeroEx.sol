pragma solidity ^0.8.9;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {LineLib} from "../utils/LineLib.sol";

contract ZeroEx {
    constructor() {}

    event Received(address token, uint256 value);
    event Sent(address token, uint256 value);

    function trade(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable returns (bool) {
        LineLib.receiveTokenOrETH(tokenIn, msg.sender, amountIn);
        emit Received(tokenIn, amountIn);
        LineLib.sendOutTokenOrETH(tokenOut, msg.sender, minAmountOut);
        emit Sent(tokenOut, minAmountOut);
        return true;
    }
}
