
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

  uint256 currentPaymentPeriodStart;
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

    bytes32 id = _createDebtPosition(lender, token, amount, amount);
    
    emit Borrow(id, amount); // loan is automatically borrowed

    // start countdown to next payment due
    currentPaymentPeriodStart = block.timestamp;
    // set end of loan
    endTime = block.timestamp + (repaymentPeriodLength * totalRepaymentPeriods);

    // also add interest rate model here?
    return true;
  }

  function _getInterestPaymentAmount(bytes32 positionId) virtual override returns(uint256) {
    // return InterestRateTerm.accrueInterest(debts[positionId].principal, repaymentPeriodLength)
  }

  function accrueInterest() external returns(uint256 accruedValue) {
    (, accruedValue) = _accrueInterest(loanPositionId);
  }

  function _close(bytes32 positionId) virtual override internal returns(bool) {
    loanStatus = LoanLib.STATUS.REPAID; // can only close if full loan is repaid
    return super._close(positionId);
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
      debt.interestRepaid += amount;

      // update global debt denominated in usd
      totalInterestAccrued -= price * amount;
      emit RepayInterest(positionId, amount);
    } else {
      // pay off interest then any overdue payments then principal
      amount -= debt.interestAccrued;
      debt.interestRepaid += debt.interestAccrued;

      // emit before set to 0
      emit RepayInterest(positionId, debt.interestAccrued);
      debt.interestAccrued = 0;
      totalInterestAccrued = 0;

      if(missedPaymentsOwed > amount) {
        emit RepayOverdue(positionId, amount);
        missedPaymentsOwed -= amount;
      } else {
        emit RepayOverdue(positionId, missedPaymentsOwed);
        missedPaymentsOwed = 0;
      }

      // missed payments get added to principal so missed payments + extra $ reduce principal
      debt.principal -= amount;
      principal -= price * amount ;

      emit RepayPrincipal(positionId, amount);
    }

    debts[positionId] = debt;

    return true;
  }
  function accrueInterest() external returns(uint256 accruedValue) {
    (, accruedValue) = _accrueInterest(loanPositionId);
  }

  function _close(bytes32 positionId) virtual override internal returns(bool) {
    loanStatus = LoanLib.STATUS.REPAID; // can only close if full loan is repaid
    return super._close(positionId);
  }

  function _healthcheck() virtual override(BaseLoan) internal returns(LoanLib.STATUS) {
    // if loan was already repaid then _healthcheck isn't called so must be defaulted
    if(block.timestamp > endTime) {
      emit Default(loanPositionId);
      return LoanLib.STATUS.LIQUIDATABLE;
    }

    uint256 timeSinceRepayment = block.timestamp - currentPaymentPeriodStart;
    // miss 1 payment? jail
    if(timeSinceRepayment > repaymentPeriodLength + GRACE_PERIOD) {
      return LoanLib.STATUS.DELINQUENT;
    }
    // believe it or not, miss 2 payments, straight to debtor jail
    if(timeSinceRepayment > repaymentPeriodLength * 2 + GRACE_PERIOD) {
      emit Default(loanPositionId);
      return LoanLib.STATUS.LIQUIDATABLE;
    }

    return BaseLoan._healthcheck();
  }

  function _getMissedPayments() virtual internal returns(uint256) {
    if(lastPaymentTimestamp + repaymentPeriodLength > block.timestamp) {
      // haven't missed a payment this cycle. may still owe from last missed cycles
      return missedPaymentsOwed;
    }

    // sol automatically rounds down so current period isn't included
    uint256 totalPeriodsMissed = (block.timestamp - lastPaymentTimestamp) / repaymentPeriodLength;

    DebtPosition memory debt = debts[loanPositionId];

    uint256 totalMissedPayments = missedPaymentsOwed + debt.interestAccrued;
    debt.principal += debt.interestAccrued;
    debt.interestAccrued = 0;
    totalInterestAccrued = 0;

    for(uint i; i <= totalPeriodsMissed; i++) {
      // update storage directly because _accrueInterest uses/updates the values
      uint256 interestOwed = _getInterestPaymentAmount(loanPositionId);
      debt.principal += interestOwed;
      totalMissedPayments += interestOwed;
    }

    return totalMissedPayments;
  }
}
