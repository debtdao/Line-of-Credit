pragma solidity 0.8.9;

import { Escrow } from "../escrow/Escrow.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { ILoan } from "../../interfaces/ILoan.sol";

abstract contract EscrowedLoan is ILoan {
  // contract holding all collateral for borrower
  Escrow immutable public escrow;

  constructor(
    uint _minimumCollateralRatio,
    address _oracle,
    address _borrower
  ) {
    escrow = new Escrow(
      _minimumCollateralRatio,
      _oracle,
      address(this),
      _borrower
    );
  }

  /** @dev see BaseLoan._healthcheck */
  function _healthcheck() virtual internal returns(LoanLib.STATUS) {
    if(escrow.getCollateralRatio() < escrow.minimumCollateralRatio()) {
      return LoanLib.STATUS.LIQUIDATABLE;
    }

    return LoanLib.STATUS.ACTIVE;
  }

  /** @dev see BaseLoan._liquidate */
  function _liquidate(
    ILoan.DebtPosition memory debt,
    bytes32 positionId,
    uint256 amount,
    address targetToken
  )
    virtual internal
    returns(uint256)
  { 
    // assumes Loan.liquidate is privileged function and sender is in charge of liquidating
    require(escrow.liquidate(amount, targetToken, msg.sender));

    emit Liquidate(positionId, amount, targetToken);

    return amount;
  }
}


