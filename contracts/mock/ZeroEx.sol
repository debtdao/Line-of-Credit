pragma solidity ^0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    returns(bool)
  {
    require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn));
    require(IERC20(tokenOut).transfer(msg.sender, minAmountOut));
    return true;
  }
}
