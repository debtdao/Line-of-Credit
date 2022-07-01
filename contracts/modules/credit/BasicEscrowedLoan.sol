import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { EscrowedLoan } from "./EscrowedLoan.sol";
import { LineOfCredit } from "./LineOfCredit.sol";
import { BaseLoan } from "./BaseLoan.sol";
import { ILoan } from "../../interfaces/ILoan.sol";

contract BasicEscrowedLoan is LineOfCredit, EscrowedLoan {

    constructor(
        address oracle_,
        address arbiter_,
        address borrower_,
        uint minCollateral_,
        uint ttl_
    ) LineOfCredit(
        oracle_,
        arbiter_,
        borrower_,
        ttl_
    ) EscrowedLoan(
        minCollateral_,
        oracle_,
        borrower_
    ) {

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
    function _healthcheck() internal override(EscrowedLoan, LineOfCredit) returns(LoanLib.STATUS) {
        return EscrowedLoan._healthcheck();
    }

}
