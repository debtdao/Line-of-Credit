import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { EscrowedLoan } from "./EscrowedLoan.sol";
import { SpigotedLoan } from "./SpigotedLoan.sol";
import { LineOfCredit } from "./LineOfCredit.sol";

contract SecuredLoan is SpigotedLoan, EscrowedLoan {

    constructor(
        address oracle_,
        address arbiter_,
        address borrower_,
        address swapTarget_,
        address spigot_,
        address escrow_,
        uint minCollateral_,
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
    ) EscrowedLoan(
        minCollateral_,
        escrow_,
        oracle_,
        borrower_
    ) {

    }


  function init() external override(LineOfCredit) virtual returns(LoanLib.STATUS) {
    return _updateLoanStatus(_init());
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
   * @param positionId -the debt position to pay down debt on
   * @param amount - amount of `targetToken` expected to be sold off in  _liquidate
   * @param targetToken - token in escrow that will be sold of to repay position
   */

  function liquidate(
    bytes32 positionId,
    uint256 amount,
    address targetToken
  )
    external
    returns(uint256)
  {
    require(msg.sender == arbiter);

    _updateLoanStatus(_healthcheck());

    require(loanStatus == LoanLib.STATUS.LIQUIDATABLE, "Loan: not liquidatable");

    // send tokens to arbiter for OTC sales
    return _liquidate(positionId, amount, targetToken, msg.sender);
  }

  
    /** @notice checks internal accounting logic for status and if ok, runs modules checks */
    function _healthcheck() internal override(EscrowedLoan, LineOfCredit) returns(LoanLib.STATUS) {
      LoanLib.STATUS s = LineOfCredit._healthcheck();
      if(s != LoanLib.STATUS.ACTIVE) {
        return s;
      }

      return EscrowedLoan._healthcheck();
    }

}
