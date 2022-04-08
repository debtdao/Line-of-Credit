import { SpigotedLoan } from "./SpigotedLoan.sol";
import { EscrowedLoan } from "./EscrowedLoan.sol";
import { BaseLoan } from "./BaseLoan.sol";
import { LoanLib } from "../../utils/LoanLib.sol";

/**
 * @title Maximum Security Debt DAO Loan
 * @author Kiba Gateaux
 * @dev NOT FOR PRODUCTION USE
 * @notice Used to test new features to ensure lender returns
 */
contract MaximumSecurityLoan is SpigotedLoan, EscrowedLoan {
  constructor(
    uint256 maxDebtValue_,
    uint256 minimumCollateralRatio_,
    address oracle_,
    address arbiter_,
    address borrower_,
    address interestRateModel_,
    address spigot_
  )
    EscrowedLoan(minimumCollateralRatio_, oracle, borrower)
    SpigotedLoan(
      maxDebtValue_,
      oracle_,
      arbiter_,
      borrower_,
      interestRateModel_,
      spigot_
    )
  {

  }
  function _healthcheck() override(EscrowedLoan, BaseLoan) internal returns(LoanLib.STATUS) {
    // check cheap calls usingi nternal data first
    if(BaseLoan._healthcheck() != LoanLib.STATUS.ACTIVE) {
      return _updateLoanStatus(BaseLoan._healthcheck());
    }
    // then call external contracts 
    return _updateLoanStatus(EscrowedLoan._healthcheck());
  }

  function _liquidate(
    bytes32 positionId,
    uint256 amount,
    address targetToken
  ) override(BaseLoan, EscrowedLoan) internal returns(uint256) {
    return EscrowedLoan._liquidate(
      positionId,
      amount,
      targetToken
    );
  }
}
