pragma solidity ^0.8.9;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { EscrowedLoan } from "./EscrowedLoan.sol";
import { SpigotedLoan } from "./SpigotedLoan.sol";
import { LineOfCredit } from "./LineOfCredit.sol";
import { ILineOfCredit } from "../../interfaces/ILineOfCredit.sol";

contract SecuredLoan is SpigotedLoan, EscrowedLoan {

    constructor(
        address oracle_,
        address arbiter_,
        address borrower_,
        address payable swapTarget_,
        address spigot_,
        address escrow_,
        uint ttl_,
        uint8 defaultSplit_
    ) SpigotedLoan(
        oracle_,
        arbiter_,
        borrower_,
        spigot_,
        swapTarget_,
        ttl_,
        defaultSplit_
    ) EscrowedLoan(escrow_) {

    }

  function _init() internal override(SpigotedLoan, EscrowedLoan) virtual returns(LoanLib.STATUS) {
     LoanLib.STATUS s =  LoanLib.STATUS.ACTIVE;
    
    if(SpigotedLoan._init() != s || EscrowedLoan._init() != s) {
      return LoanLib.STATUS.UNINITIALIZED;
    }
    
    return s;
  }


  // Liquidation
  /**
   * @notice - Forcefully take collateral from borrower and repay debt for lender
   * @dev - only called by neutral arbiter party/contract
   * @dev - `loanStatus` must be LIQUIDATABLE
   * @dev - callable by `arbiter`
   * @param amount - amount of `targetToken` expected to be sold off in  _liquidate
   * @param targetToken - token in escrow that will be sold of to repay position
   */

  function liquidate(
    uint256 amount,
    address targetToken
  )
    external
    whileBorrowing
    returns(uint256)
  {
    if(msg.sender != arbiter) { revert CallerAccessDenied(); }
    if(_updateStatus(_healthcheck()) != LoanLib.STATUS.LIQUIDATABLE) {
      revert NotLiquidatable();
    }

    // send tokens to arbiter for OTC sales
    return _liquidate(ids[0], amount, targetToken, msg.sender);
  }

  
    /** @notice checks internal accounting logic for status and if ok, runs modules checks */
    function _healthcheck() internal override(EscrowedLoan, LineOfCredit) returns(LoanLib.STATUS) {
      LoanLib.STATUS s = LineOfCredit._healthcheck();
      if(s != LoanLib.STATUS.ACTIVE) {
        return s;
      }

      return EscrowedLoan._healthcheck();
    }


    /// @notice all insolvency conditions must pass for call to succeed
    function _canDeclareInsolvent()
      internal
      virtual
      override(EscrowedLoan, SpigotedLoan)
      returns(bool)
    {
      return (
        EscrowedLoan._canDeclareInsolvent() &&
        SpigotedLoan._canDeclareInsolvent()
      );
    }

}
