
pragma solidity ^0.8.9;

import { BaseLoan } from "./BaseLoan.sol";
import { LoanLib } from "../../lib/LoanLib.sol";

abstract contract TermLoan {
  LoanLib.STATUS loanStatus;
  uint256 public termLength;
  uint256 public termsUntilDelinquent;
  uint256 public lastPaymentTimestamp;
  constructor(
    uint256 termLength_,
    uint256 termsUntilDelinquent_
  ) {
    termLength = termLength_;
    termsUntilDelinquent = termsUntilDelinquent_;
  }


  function _liquidate() virtual internal {
    require(loanStatus == LoanLib.STATUS.DELINQUENT);
    loanStatus = LoanLib.STATUS.LIQUIDATABLE;
  }
  function _init() virtual internal returns(bool) {
    lastPaymentTimestamp = block.timestamp;
    return true;
  }

  function _healthcheck() virtual internal returns(LoanLib.STATUS) {
    if(block.timestamp - lastPaymentTimestamp > termLength * termsUntilDelinquent) {
      return LoanLib.STATUS.DELINQUENT;
    }
  }
}
