pragma solidity ^0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LoanLib } from "../utils/LoanLib.sol";

contract ZeroEx {
  constructor () {

  }


  function trade(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut
  )
    external
    payable
    returns(bool)
  {
    LoanLib.receiveTokenOrETH(tokenIn, msg.sender, amountIn);
    LoanLib.sendOutTokenOrETH(tokenOut, msg.sender, minAmountOut);
    return true;
  }
}
