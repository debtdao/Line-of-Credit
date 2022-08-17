pragma solidity 0.8.9;

import { IEscrow } from "../interfaces/IEscrow.sol";
import { LoanLib } from "../utils/LoanLib.sol";

contract MockLoan {

    uint debtValueUSD;
    address escrow;
    address public arbiter;
    LoanLib.STATUS public loanStatus;

    constructor(uint _debt, address arbiter_) public {
        debtValueUSD = _debt;
        // console.log("arbiter", msg.sender);
        arbiter = arbiter_;
        loanStatus =  LoanLib.STATUS.ACTIVE;
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


    function setStatus(LoanLib.STATUS _status) external {
        loanStatus = _status;
    }

    function liquidate(uint positionId, uint amount, address token, address to) external {
        require(msg.sender == arbiter);
        IEscrow(escrow).liquidate(amount, token, to);
    }

    function accrueInterest() external pure returns(uint256) {
        return 0;
    }

    function updateOutstandingDebt() external view returns(uint256,uint256) {
        return (debtValueUSD, 0);
    }

}
