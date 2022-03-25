pragma solidity ^0.8.9;

// Helpers
import { TermLoan } from "./TermLoan.sol";

abstract contract NoEarlyRepaymentLoan is TermLoan {
  constructor(
    uint256 maxDebtValue_,
    address oracle_,
    address arbiter_,
    address borrower_,
    address escrow_,
    address interestRateModel_,
    uint256 termLength_,
    uint256 termsUntilDelinquent_
  )
    TermLoan(
      maxDebtValue_,
      oracle_,
      arbiter_,
      borrower_,
      escrow_,
      interestRateModel_,
      termLength_,
      termsUntilDelinquent_
    )
  {

  }

  function _getMaxRepayableAmount(DebtPosition memory debt) virtual override internal returns(uint256) {
    // no early repayment until term is over
    if(block.timestamp - lastPaymentTimestamp < termLength) {
      return 0;
    }

    return super._getMaxRepayableAmount(debt);
  }
}
