pragma solidity 0.8.9;

import  {EscrowedLine} from "../modules/credit/EscrowedLine.sol";
import { IEscrowedLine } from "../interfaces/IEscrowedLine.sol";
import {LineOfCredit} from "../modules/credit/LineOfCredit.sol";
import {LineLib} from "../utils/LineLib.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {CreditLib} from "../../utils/CreditLib.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";

contract MockEscrowedLine is EscrowedLine, LineOfCredit {
    
    
    constructor(
        address _escrow,
        address oracle_,
        address arbiter_,
        address borrower_,
        uint ttl_
        ) EscrowedLine(_escrow)
    LineOfCredit(oracle_, arbiter_, borrower_, ttl_){
        
    }
    

  function _init() internal override(EscrowedLine, LineOfCredit) returns(LineLib.STATUS) {
    if(escrow.line() != address(this)) return LineLib.STATUS.UNINITIALIZED;
    return LineLib.STATUS.ACTIVE;
  }

  /** @dev see BaseLine._healthcheck */
  function _healthcheck() override(EscrowedLine, LineOfCredit) internal returns(LineLib.STATUS) {
    if(escrow.isLiquidatable()) {
      return LineLib.STATUS.LIQUIDATABLE;
    }

    return LineLib.STATUS.ACTIVE;
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
    override internal
    returns(uint256)
  { 
    require(escrow.liquidate(amount, targetToken, to));

    emit Liquidate(positionId, amount, targetToken);

    return amount;
  }

  /**
   * @notice require all collateral sold off before declaring insolvent
   *(@dev priviliegad internal function.
   * @return if line is insolvent or not
  */
  function _canDeclareInsolvent() internal override(EscrowedLine, LineOfCredit) returns(bool) {
    if(escrow.getCollateralValue() != 0) { revert NotInsolvent(address(escrow)); }
    return true;
  }

  function _rollover(address newLine) internal override returns(bool) {
    require(escrow.updateLine(newLine));
    return true;
  }

  function liquidate(
    uint256 amount,
    address targetToken
  )
    external
    whileBorrowing
    returns(uint256)
  {
    if(msg.sender != arbiter) { revert CallerAccessDenied(); }
    if(_updateStatus(_healthcheck()) != LineLib.STATUS.LIQUIDATABLE) {
      revert NotLiquidatable();
    }

    // send tokens to arbiter for OTC sales
    return _liquidate(ids[0], amount, targetToken, msg.sender);
  }
    


}