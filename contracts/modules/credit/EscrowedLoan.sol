pragma solidity 0.8.9;

import { Escrow } from "../escrow/Escrow.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { IEscrowedLoan } from "../../interfaces/IEscrowedLoan.sol";
import { ILineOfCredit } from "../../interfaces/ILineOfCredit.sol";

abstract contract EscrowedLoan is IEscrowedLoan, ILineOfCredit {
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
    if(escrow.isLiquidatable()) {
      return LoanLib.STATUS.LIQUIDATABLE;
    }

    return LoanLib.STATUS.ACTIVE;
  }

  /**
   * @notice sends escrowed tokens to liquidation. 
   *(@dev priviliegad function. Do checks before calling.
   * @param positionId - position being repaid in liquidation
   * @param amount - amount of tokens to take from escrow and liquidate
   * @param targetToken - the token to take from escrow
   * @param to - the liquidator to send tokens to. could be OTC address or smart contract
   * @return amount - the total amount of `targetToken` sold to repay credit
   *  
  */
  function _liquidate(
    bytes32 positionId,
    uint256 amount,
    address targetToken,
    address to
  )
    virtual internal
    returns(uint256)
  { 
    require(escrow.liquidate(amount, targetToken, to));

    emit Liquidate(positionId, amount, targetToken);

    return amount;
  }

  /**
   * @notice require all collateral sold off before declaring insolvent
   *(@dev priviliegad internal function.
   * @return if loan is insolvent or not
  */
  function _declareInsolvent() internal virtual returns(bool) {
    if(escrow.getCollateralValue() != 0) { revert NotInsolvent(address(escrow)); }
    return true;
  }
}


