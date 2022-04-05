pragma solidity ^0.8.9;

// Helpers
import { TermLoan } from "./TermLoan.sol";
import { ILoan } from "../../interfaces/ILoan.sol";

abstract contract NoEarlyRepaymentLoan is TermLoan {
  constructor(
    uint256 termLength_,
    uint256 termsUntilDelinquent_
  )
    TermLoan(termLength_, termsUntilDelinquent_)
  {

  }

  function _getMaxRepayableAmount(ILoan.DebtPosition memory debt) virtual override internal returns(uint256) {
    // no early repayment until term is over
    if(block.timestamp - lastPaymentTimestamp < termLength) {
      return 0;
    }

    return super._getMaxRepayableAmount(debt);
  }
}
