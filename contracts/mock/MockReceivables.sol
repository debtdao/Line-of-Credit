pragma solidity 0.8.9;

import { LineLib } from "../utils/LineLib.sol";

contract MockReceivables {

  function balance(address token) external returns(uint256) {
    return LineLib.getBalance(token);
  }

  function accept(address token, address from, uint256 amount) external  payable {
    LineLib.receiveTokenOrETH(token, from, amount);
  }

  function send(address token, address to, uint256 amount) external  payable {
    LineLib.sendOutTokenOrETH(token, to, amount);
  }


}

contract MockStatefulReceivables is MockReceivables {

    bool receiveEnabled = true;

    function setReceiveableState(bool state) external {
      receiveEnabled = state;
    }

    function acceptOverPayment(address token, address from, uint256 amount, uint256 extra) external payable {
      LineLib.receiveTokenOrETH(token, from, amount + extra);
    }

    receive() external payable {
      if(!receiveEnabled) revert();
    }
}