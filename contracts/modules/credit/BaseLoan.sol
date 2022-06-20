pragma solidity ^0.8.9;

// Helpers
import { LoanLib } from "../../utils/LoanLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// module interfaces 
import { ILoan } from "../../interfaces/ILoan.sol";
import { IEscrow } from "../../interfaces/IEscrow.sol";
import { IOracle } from "../../interfaces/IOracle.sol";

abstract contract BaseLoan is ILoan {  
  address immutable public borrower;   // borrower being lent to
  IOracle immutable public oracle; 
  address immutable public arbiter;

  // Loan Financials aggregated accross all existing  DebtPositions
  LoanLib.STATUS public loanStatus;

  uint256 public principalUsd;  // initial principal
  uint256 public interestUsd;   // unpaid interest


  /**
   * @dev - Loan borrower and proposed lender agree on terms
            and add it to potential options for borrower to drawdown on
            Lender and borrower must both call function for MutualUpgrade to add debt position to Loan
   * @param oracle_ - price oracle to use for getting all token values
   * @param arbiter_ - neutral party with some special priviliges on behalf of borrower and lender
   * @param borrower_ - the debitor for all debt positions in this contract
  */
  constructor(
    address oracle_,
    address arbiter_,
    address borrower_
  ) {
    borrower = borrower_;
    arbiter = arbiter_;
    oracle = IOracle(oracle_);

    loanStatus = LoanLib.STATUS.INITIALIZED;

    emit DeployLoan(
      oracle_,
      arbiter_,
      borrower_
    );
  }

  ///////////////
  // MODIFIERS //
  ///////////////

  modifier isActive() {
    require(loanStatus == LoanLib.STATUS.ACTIVE, 'Loan: no op');
    _;
  }

  modifier onlyBorrower() {
    require(msg.sender == borrower, 'Loan: only borrower');
    _;
  }

  modifier onlyArbiter() {
    require(msg.sender == arbiter, 'Loan: only arbiter');
    _;
  }


  ///////////
  // HOOKS //
  ///////////

  /**
   * @dev  Used to addc custom liquidation functionality until we create separate Liquidation module
   * @param positionId - deterministic id of loan
   * @param amount - expected amount of `targetToken` to be liquidated
   * @param targetToken - token to liquidate to repay debt
   * @return amount of tokens actually liquidated
  */
  function _liquidate(
    bytes32 positionId,
    uint256 amount,
    address targetToken
  )
    virtual internal
    returns(uint256)
  {
    return 0;
  }

  function healthcheck() external returns(LoanLib.STATUS) {
    return _updateLoanStatus(_healthcheck());
  }
  /**
   * @notice - returns early if returns non-ACTIVE
   * @dev - BaseLoan._healthcheck MUST always come first in inheritence conflicts before running other checks
          - e.g. if(BaseLoan._healthcheck() == ACTIVE) { return EscrowLoan._healthcheck() } 
  */
  function _healthcheck() virtual internal returns(LoanLib.STATUS status) {
    // if loan is in a final end state then do not run _healthcheck()
    if(loanStatus == LoanLib.STATUS.REPAID || loanStatus == LoanLib.STATUS.INSOLVENT) {
      return loanStatus;
    }

    return LoanLib.STATUS.ACTIVE;
  }


  // Liquidation
  /**
   * @notice - Forcefully take collateral from borrower and repay debt for lender
   * @dev - only called by neutral arbiter party/contract
   * @dev - `loanStatus` must be LIQUIDATABLE
   * @param positionId -the debt position to pay down debt on
   * @param amount - amount of `targetToken` expected to be sold off in  _liquidate
   * @param targetToken - token that is expected to be sold of to repay positionId
   */

  function liquidate(
    bytes32 positionId,
    uint256 amount,
    address targetToken
  )
    onlyArbiter
  
    external
    returns(uint256)
  {
    _updateLoanStatus(_healthcheck());
    require(loanStatus == LoanLib.STATUS.LIQUIDATABLE, "Loan: not liquidatable");
    return _liquidate(positionId, amount, targetToken);
  }

  // Helper functions
  function _updateLoanStatus(LoanLib.STATUS status) internal returns(LoanLib.STATUS) {
    if(loanStatus == status) return loanStatus;
    loanStatus = status;
    emit UpdateLoanStatus(uint256(status));
    return status;
  }

  /**
   * @dev - Calls Oracle module to get most recent price for token.
            All prices denominated in USD.
   * @param token - token to get price for
  */
  function _getTokenPrice(address token) internal returns (uint256) {
    return IOracle(oracle).getLatestAnswer(token);
  }
}
