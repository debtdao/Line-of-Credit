
pragma solidity ^0.8.9;

import { BaseLoan } from "./BaseLoan.sol";
import { ISpigotedLoan } from "../../interfaces/ISpigotedLoan.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { ISpigotConsumer } from "../../interfaces/ISpigotConsumer.sol";

contract SpigotedLoan is BaseLoan, ISpigotedLoan {
  address immutable public spigot;

    /**
   * @dev - BaseLoan contract with additional functionality for integrating with Spigot and borrower revenue streams to repay loans
   * @param maxDebtValue_ - total debt accross all lenders that borrower is allowed to create
   * @param oracle_ - price oracle to use for getting all token values
   * @param spigot_ - contract securing/repaying loan from borrower revenue streams
   * @param arbiter_ - neutral party with some special priviliges on behalf of borrower and lender
   * @param borrower_ - the debitor for all debt positions in this contract
   * @param interestRateModel_ - contract calculating lender interest from debt position values
  */
  constructor(
    uint256 maxDebtValue_,
    address oracle_,
    address arbiter_,
    address borrower_,
    address interestRateModel_,
    address spigot_
  )
    BaseLoan(maxDebtValue_, oracle_, arbiter_, borrower_, interestRateModel_)
  {
    spigot = spigot_;

    loanStatus = LoanLib.STATUS.INITIALIZED;
  }

 /**
   * @dev - Claims revenue tokens from Spigot attached to borrowers revenue generating tokens
            and sells them via 0x protocol to repay debts
            Only callable by borrower for security pasing arbitrary data in contract call
            and they are most incentivized to get best price on assets being sold.
   * @notice see _repay() for more details
   * @param positionId -the debt position to pay down debt on
   * @param claimToken - The revenue token escrowed by Spigot to claim and use to repay debt
   * @param zeroExTradeData - data generated by 0x API to trade `claimToken` against their exchange contract
  */
  function claimSpigotAndRepay(
    bytes32 positionId,
    address claimToken,
    bytes calldata zeroExTradeData
  )
    onlyBorrower
    validPositionId(positionId)
    external
    returns(bool)
  {

    _accrueInterest();
    DebtPosition memory debt = debts[positionId];

    // need to check with 0x api on where bought tokens go to by default
    // see if we can change that to Loan instead of SpigotConsumer
    uint256 tokensBought = ISpigotConsumer(spigot).claimAndTrade(
      claimToken,
      debt.token,
      zeroExTradeData
    );

    // TODO check if early repayment is allowed on loan
    // then update logic here. Probs need an internal func
    uint256 amountToRepay = _getMaxRepayableAmount(positionId, tokensBought);

    // claim bought tokens from spigot to repay loan
    require(
      ISpigotConsumer(spigot).stream(address(this), debt.token, amountToRepay),
      'Loan: failed repayment'
    );

    _repay(positionId, amountToRepay);

    emit RevenuePayment(
      claimToken,
      _getTokenPrice(debt.token) * amountToRepay
    );

    return true;
  }
}
