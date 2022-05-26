
pragma solidity ^0.8.9;

import { BaseLoan } from "./BaseLoan.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { ITermLoan } from "../../interfaces/ITermLoan.sol";
import { InterestRateTerm } from "../interest-rate/InterestRateTerm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract TermLoan is BaseLoan, ITermLoan {
  uint256 constant GRACE_PERIOD = 1 days;

  uint256 immutable repaymentPeriodLength;
  uint256 immutable totalRepaymentPeriods;

  InterestRateTerm immutable interestRate;
  
  // helper var.
  // time when loan is done
  uint256 endTime;
  // principal for compounding interest or amoratization
  uint256 initialPrincipal;

  // the only loan allowed on this contract. set in addDebtPosition()
  bytes32 loanPositionId;

  uint256 currentPaymentPeriodStart;
  uint256 overduePaymentsAmount;

  // track if interest has already been calculated for this payment period since _accrueInterest is called in multiple places
  mapping(uint256 => bool) isInterestAccruedForPeriod; // paymemnt period timestamp -> has interest accrued

  constructor(
    uint256 repaymentPeriodLength_,
    uint256 totalRepaymentPeriods_,
    uint256 interestRateBps
  ) {
    repaymentPeriodLength = repaymentPeriodLength_;
    totalRepaymentPeriods = totalRepaymentPeriods_;
    interestRate = new InterestRateTerm(interestRateBps);
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
    initialPrincipal = principal;

    // also add interest rate model here?
    return true;
  }

  function _getInterestPaymentAmount(bytes32 positionId)
    virtual override
    internal
    returns(uint256)
  {
    // dont add interest if already charged for period
    if(isInterestAccruedForPeriod[currentPaymentPeriodStart]) return 0;

    uint256 outstandingdDebt = debts[positionId].principal + debts[positionId].interestAccrued;
    
    return interestRate.accrueInterest(outstandingdDebt);
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
      totalInterestAccrued -= price * amount / debt.decimals;
      emit RepayInterest(positionId, amount);
    } else {
      // pay off interest then any overdue payments then principal
      amount -= debt.interestAccrued;
      debt.interestRepaid += debt.interestAccrued;

      // emit before set to 0
      emit RepayInterest(positionId, debt.interestAccrued);
      debt.interestAccrued = 0;
      totalInterestAccrued = 0;

      if(overduePaymentsAmount > amount) {
        emit RepayOverdue(positionId, amount);
        overduePaymentsAmount -= amount;

      } else {
        emit RepayOverdue(positionId, overduePaymentsAmount);
        overduePaymentsAmount = 0;
      }

      // missed payments get added to principal so missed payments + extra $ reduce principal
      debt.principal -= amount;
      principal -= price * amount ;

      emit RepayPrincipal(positionId, amount);
    }

    currentPaymentPeriodStart += repaymentPeriodLength + 1; // can only repay once per peridd, 

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
    if(_isEnd() && principal > 0) {
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

    if(missedPaymentsOwed > 0) {
      // they mde a recent payment but are behind on payments overalls
      return LoanLib.STATUS.DELINQUENT;
    }



    return BaseLoan._healthcheck();
  }

  /**
   * @notice returns true if is last payment period of loan or later
   * @dev 
   */
  function _isEnd() internal view returns(bool) {
    return (
      endTime > block.timestamp ||
      endTime - block.timestamp <= repaymentPeriodLength
    );
  }

}
