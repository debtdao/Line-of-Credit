pragma solidity ^0.8.9;

// Helpers
import { TermLoan } from "./TermLoan.sol";
import { ILoan } from "../../interfaces/ILoan.sol";
import { LoanLib } from "../../utils/LoanLib.sol";

abstract contract BulletLoan is TermLoan {
  constructor(
    uint256 repaymentPeriodLength_,
    uint256 totalRepaymentPeriods_
  )
    TermLoan(repaymentPeriodLength_, totalRepaymentPeriods_)
  {

  }

  function _getMaxRepayableAmount(bytes32 positionId, uint256 requestedRepayAmount)
    virtual override
    internal
    returns(uint256) {

    if(block.timestamp - currentPaymentPeriodStart < repaymentPeriodLength) {
      return 0;
    }

    missedPaymentsOwed = _getMissedPayments();

    uint256 totalOwed;
    bool isEnd = endTime - block.timestamp <= repaymentPeriodLength;

    // must already _accrueInterest in depositAndRepay/_getMissedPayments
    totalOwed = isEnd ? 
      // loan has ended. repay all principal + interest
      debts[positionId].principal + debts[positionId].interestAccrued + missedPaymentsOwed :
      // normal interest payment
      debts[positionId].interestAccrued + missedPaymentsOwed;

    // _get shouldn't have side effects i feel like
    if(requestedRepayAmount < totalOwed) {
      totalOwed = requestedRepayAmount;
      // if they can't make full payment then update status. if loan is ended that means they cant repay and is insolvent
      if(isEnd) {
        emit Default(positionId);
        _updateLoanStatus(LoanLib.STATUS.LIQUIDATABLE);
      } else {
        _updateLoanStatus(LoanLib.STATUS.DELINQUENT);
      }
    }

    return totalOwed;
  }

  function _getMissedPayments() override internal view returns(uint256) {
    // check how many epochs have passed
    // loop over periods and constantly accrue interest, add to principal, calculate interest for next period based of this
    // might be best as recursive func, idk design yet

  }
}
