import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseLoan } from "./BaseLoan.sol";
contract RevolverLoan is BaseLoan {
  bytes32[] positionIds; // all active positions

  constructor(
    uint256 maxDebtValue_,
    address oracle_,
    address arbiter_,
    address borrower_,
    address interestRateModel_
  ) BaseLoan(
    maxDebtValue_,
    oracle_,
    arbiter_,
    borrower_,
    interestRateModel_
  ) {

  }
  /**
   * @dev - Loan borrower and proposed lender agree on terms
            and add it to potential options for borrower to drawdown on
            Lender and borrower must both call function for MutualUpgrade to add debt position to Loan
   * @param amount - amount of `token` to initially deposit
   * @param token - the token to be lent out
   * @param lender - address that will manage debt position 
  */
  function addDebtPosition(
    uint256 amount,
    address token,
    address lender
  )
    isActive
    mutualUpgrade(lender, borrower) 
    virtual
    override
    external
    returns(bool)
  {
    bool success = IERC20(token).transferFrom(
      lender,
      address(this),
      amount
    );
    require(success, 'Loan: no tokens to lend');


    _createDebtPosition(lender, token, amount);

    positionIds.push(positionId);

    // also add interest rate model here?
    return true;
  }

  /**
    @notice see _accrueInterest()
  */
  function accrueInterest() override external returns(uint256 accruedValue) {
    uint256 len = positionIds.length;

    for(uint256 i = 0; i < len; i++) {
      (, uint256 accruedTokenValue) = _accrueInterest(positionIds[len]);
      accruedValue += accruedTokenValue;
    }

    totalInterestAccrued += accruedValue;
    return accruedValue;
  }

   /**
   * @dev - Reduces `principal` and/or `interestAccrued` on debt position, increases lender's `deposit`.
            Reduces global USD principal and totalInterestAccrued values.
            Expects checks for conditions of repaying and param sanitizing before calling
            e.g. early repayment of principal, tokens have actually been paid by borrower, etc.
   * @param positionId - debt position struct with all data pertaining to loan
   * @param amount - amount of token being repaid on debt position
  */
  function _repay(
    bytes32 positionId,
    uint256 amount
  )
    override
    internal
    returns(bool)
  {
    // move all this logic to Revolver.sol
    DebtPosition memory debt = debts[positionId];
    
    uint256 price = _getTokenPrice(debt.token);

    if(amount <= debt.interestAccrued) {
      debt.interestAccrued -= amount;
      totalInterestAccrued -= price * amount;
      emit RepayInterest(positionId, amount);
    } else {
      uint256 principalPayment = amount - debt.interestAccrued;
      // update global debt denominated in usd
      principal -= price * principalPayment;
      totalInterestAccrued -= price * debt.interestAccrued;

      emit RepayPrincipal(positionId, principalPayment);
      // update before set to 0
      emit RepayInterest(positionId, debt.interestAccrued);
      
      // update individual debt position denominated in token
      debt.principal -= principalPayment;
      // TODO update debt.deposit here or _accureInterest()?
      debt.interestAccrued = 0;
    }


    return true;
  }

  function _close(bytes32 positionId) virtual override returns(bool) {
    // remove from active list
    positionIds = LoanLib.removePosition(positionIds, positionId);

    // brick loan contract if all positions closed
    if(positionIds.length == 0) {
      loanStatus = LoanLib.STATUS.REPAID;
    }

    return super._close(positionId);
  }
}
