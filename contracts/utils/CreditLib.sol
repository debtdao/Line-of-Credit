pragma solidity 0.8.9;
import { ILineOfCredit } from "../interfaces/ILineOfCredit.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IInterestRateCredit } from "../interfaces/IInterestRateCredit.sol";
import { ILoan } from "../interfaces/ILoan.sol";

/**
  * @title Debt DAO P2P Loan Library
  * @author Kiba Gateaux
  * @notice Core logic and variables to be reused across all Debt DAO Marketplace loans
 */
library CreditLib {

  event WithdrawDeposit(bytes32 indexed id, uint256 indexed amount);
  // lender removing funds from Loan  principal
  event WithdrawProfit(bytes32 indexed id, uint256 indexed amount);
  // lender taking interest earned out of contract

  event InterestAccrued(bytes32 indexed id, uint256 indexed amount);
  // interest added to borrowers outstanding balance


  // Borrower Events

  event Borrow(bytes32 indexed id, uint256 indexed amount);
  // receive full loan or drawdown on credit

  event RepayInterest(bytes32 indexed id, uint256 indexed amount);

  event RepayPrincipal(bytes32 indexed id, uint256 indexed amount);

  // move token valuation shit here too

  function repay(
    ILineOfCredit.Credit memory credit,
    bytes32 id,
    uint256 amount
  )
    external
    // TODO don't need to return all uints if we can get events working in library to show up on subgraph
    returns (ILineOfCredit.Credit memory)
  {
      if (amount <= credit.interestAccrued) {
          credit.interestAccrued -= amount;
          credit.interestRepaid += amount;
          emit RepayInterest(id, amount);
          return credit;
      } else {
          uint256 interest = credit.interestAccrued;
          uint256 principalPayment = amount - interest;


          // update individual credit position denominated in token
          credit.principal -= principalPayment;
          credit.interestRepaid += interest;
          credit.interestAccrued = 0;

          emit RepayInterest(id, interest);
          emit RepayPrincipal(id, principalPayment);

          return credit;
      }

  }

  function withdraw(
    ILineOfCredit.Credit memory credit,
    bytes32 id,
    uint256 amount
  )
    external
    returns (ILineOfCredit.Credit memory)
  {

      if(amount > credit.deposit + credit.interestRepaid - credit.principal) {
        revert ILineOfCredit.NoLiquidity(id);
      }

      if (amount > credit.interestRepaid) {
          uint256 interest = credit.interestRepaid;
          amount -= interest;

          credit.deposit -= amount;
          credit.interestRepaid = 0;

          // emit events before seeting to 0
          emit WithdrawDeposit(id, amount);
          emit WithdrawProfit(id, interest);

          return credit;
      } else {
          credit.interestRepaid -= amount;
          emit WithdrawProfit(id, amount);
          return credit;
      }
  }


  function accrue(
    ILineOfCredit.Credit memory credit,
    bytes32 id,
    IInterestRateCredit interest
  )
    external
    returns (ILineOfCredit.Credit memory)
  {
        // get token demoninated interest accrued
        uint256 accruedToken = interest.accrueInterest(
            id,
            credit.principal,
            credit.deposit
        );

        // update credits balance
        credit.interestAccrued += accruedToken;

        emit InterestAccrued(id, accruedToken);
        return credit;
  }

}
