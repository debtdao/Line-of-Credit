pragma solidity 0.8.9;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleRevenueContract {
    address owner;
    IERC20 revenueToken;

    constructor(address _owner, address token) {
        owner = _owner;
        revenueToken = IERC20(token);
    }

    function claimPullPayment() external returns(bool) {
        require(msg.sender == owner, "Revenue: Only owner can claim");
        require(revenueToken.transfer(owner, revenueToken.balanceOf(address(this))), "Revenue: bad transfer");
        return true;
    }

    function sendPushPayment() external returns(bool) {
        require(revenueToken.transfer(owner, revenueToken.balanceOf(address(this))));
        return true;
    }

    function doAnOperationsThing() external returns(bool)  {
        require(msg.sender == owner);
        return true;
    }

    function transferOwnership(address newOwner) external returns(bool) {
        require(msg.sender == owner);
        owner = newOwner;
        return true;
    }

}
