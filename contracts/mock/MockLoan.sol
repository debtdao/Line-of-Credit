pragma solidity 0.8.9;

import { IEscrow } from "../interfaces/IEscrow.sol";

contract MockLoan {

    uint debtValueUSD;
    address escrow;
    address public arbiter;

    constructor(uint _debt) public {
        debtValueUSD = _debt;
        // console.log("arbiter", msg.sender);
        arbiter = msg.sender;
    }

    function setEscrow(address _escrow) public {
        escrow = _escrow;
    }


    function setArbiter(address _arbiter) public {
        arbiter = _arbiter;
    }

    function setDebtValue(uint _debt) external {
        debtValueUSD = _debt;
    }

    function liquidate(uint positionId, uint amount, address token, address to) external {
        IEscrow(escrow).liquidate(amount, token, to);
    }

    function accrueInterest() external returns(uint256) {
        return 0;
    }

    function getOutstandingDebt() external returns(uint256) {
        return debtValueUSD;
    }

}
