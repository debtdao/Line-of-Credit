import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { EscrowedLoan } from "./EscrowedLoan.sol";
import { RevolverLoan } from "./RevolverLoan.sol";
import { BaseLoan } from "./BaseLoan.sol";
import { ILoan } from "../../interfaces/ILoan.sol";

contract BasicEscrowedLoan is RevolverLoan, EscrowedLoan {

    constructor(
        uint256 maxDebtValue_,
        address oracle_,
        address arbiter_,
        address borrower_,
        address interestRateModel_,
        uint minCollateral_
    ) RevolverLoan(
        maxDebtValue_,
        oracle_,
        arbiter_,
        borrower_,
        interestRateModel_
    ) EscrowedLoan(
        minCollateral_,
        oracle_,
        borrower_
    ) {

    }

    function _getInterestPaymentAmount(bytes32 positionId) override internal returns(uint256)
    {
        // NB: overriden so that _accrueInterest (out of scope) does not revert
        return 0;
    }

    /** @dev see BaseLoan._liquidate */
    function _liquidate(
        bytes32 positionId,
        uint256 amount,
        address targetToken
    )
    internal override(BaseLoan, EscrowedLoan)
    returns(uint256)
    {
        return EscrowedLoan._liquidate(positionId, amount, targetToken);
    }

    /** @dev see BaseLoan._healthcheck */
    function _healthcheck() internal override(EscrowedLoan, BaseLoan) returns(LoanLib.STATUS) {
        return EscrowedLoan._healthcheck();
    }

}
