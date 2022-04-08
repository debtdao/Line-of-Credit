
pragma solidity ^0.8.9;

import { BaseLoan } from "./BaseLoan.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { ITermLoan } from "../../interfaces/ITermLoan.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract TermLoan is BaseLoan, ITermLoan {
  uint256 constant GRACE_PERIOD = 1 days;

  uint256 immutable repaymentPeriodLength;
  uint256 immutable totalRepaymentPeriods;
  
  // helper var. time when loan is done
  uint256 endTime;

  // the only loan allowed on this contract. set in addDebtPosition()
  bytes32 loanPositionId;

  uint256 lastPaymentTimestamp;
  uint256 missedPaymentsOwed;

  constructor(
    uint256 repaymentPeriodLength_,
    uint256 totalRepaymentPeriods_
  ) {
    repaymentPeriodLength = repaymentPeriodLength_;
    totalRepaymentPeriods = totalRepaymentPeriods_;
  }

  function addDebtPosition(
    uint256 amount,
    address token,
    address lender
  )
    isActive
    mutualUpgrade(lender, borrower) 
    virtual
    external
    returns(bool)
  {
    require(loanPositionId == bytes32(0), 'Loan: only 1 position');

    // send tokens directly to borrower because loan activates starts immediately
    bool success = IERC20(token).transferFrom(
      lender,
      borrower,
      amount
    );
    require(success, 'Loan: deposit failed');

    bytes32 id = _createDebtPosition(lender, token, amount);
    
     // tokens already sent so set principal to loan amount
    debts[id].principal = amount;

    // start countdown to next payment due
    lastPaymentTimestamp = block.timestamp;
    // set end of loan
    endTime = block.timestamp + (repaymentPeriodLength * totalRepaymentPeriods);

    // also add interest rate model here?
    return true;
  }
  function accrueInterest() external returns(uint256 accruedValue) {
    (, accruedValue) = _accrueInterest(loanPositionId);
    totalInterestAccrued += accruedValue;
  }

  function _repay(
    bytes32 positionId,
    uint256 amount
  ) override internal returns(bool) {
        // move all this logic to Revolver.sol
    DebtPosition memory debt = debts[positionId];
    
    uint256 price = _getTokenPrice(debt.token);

    if(amount <= debt.interestAccrued) {
      // simple interest payment
      
      debt.interestAccrued -= amount;

      // update global debt denominated in usd
      totalInterestAccrued -= price * amount;
      emit RepayInterest(positionId, amount);
    } else {
      // pay off interest then any overdue payments then principal

      amount -= debt.interestAccrued;
      totalInterestAccrued -= price * debt.interestAccrued;
      // emit before set to 0
      emit RepayInterest(positionId, debt.interestAccrued);
      debt.interestAccrued = 0;

      if(missedPaymentsOwed > amount) {
        // not enough to payback all past due or take out principal

        // TODO  we should also be reducing principal here right?????
        missedPaymentsOwed -= amount;
        emit RepayOverdue(positionId, amount);
      } else {
        amount -= missedPaymentsOwed;
        // emit 
        emit RepayOverdue(positionId, missedPaymentsOwed);
        missedPaymentsOwed = 0;

        debt.principal -= amount;
        principal -= price * amount ;
        emit RepayPrincipal(positionId, amount);
      }
      
      // TODO update debt.accruedInterst here
    }

    return true;
  }

  function _healthcheck() virtual override(BaseLoan) internal returns(LoanLib.STATUS) {
    // if loan was already repaid then this _healthcheck shouldn't be called so loan wasn't repaid
    if(block.timestamp > endTime) {
      // should be INSOLVENT? 
      return LoanLib.STATUS.LIQUIDATABLE;
    }

    uint256 timeSinceRepayment = block.timestamp - lastPaymentTimestamp;
    // miss 1 payment? jail
    if(timeSinceRepayment > repaymentPeriodLength + GRACE_PERIOD) {
      return LoanLib.STATUS.DELINQUENT;
    }
    // believe it or not, miss 2 payments, straight to debtor jail
    if(timeSinceRepayment > repaymentPeriodLength * 2 + GRACE_PERIOD) {
      return LoanLib.STATUS.LIQUIDATABLE;
    }

    return BaseLoan._healthcheck();
  }

  function _getMissedPayments() virtual internal view returns(uint256 totalMissedPayments) {}
}
