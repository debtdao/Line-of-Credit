pragma solidity 0.8.9;
import { ILineOfCredit } from "../interfaces/ILineOfCredit.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IInterestRateCredit } from "../interfaces/IInterestRateCredit.sol";
import { ILoan } from "../interfaces/ILoan.sol";
import { LoanLib } from "./LoanLib.sol";

/**
  * @title Debt DAO P2P Loan Library
  * @author Kiba Gateaux
  * @notice Core logic and variables to be reused across all Debt DAO Marketplace loans
 */
library CreditLib {

    event AddCredit(
        address indexed lender,
        address indexed token,
        uint256 indexed deposit,
        bytes32 positionId
    );

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


  error NoTokenPrice();

  error PositionExists();


  /**
   * @dev          - Create deterministic hash id for a debt position on `loan` given position details
   * @param loan   - loan that debt position exists on
   * @param lender - address managing debt position
   * @param token  - token that is being lent out in debt position
   * @return positionId
   */
  function computePositionId(
    address loan,
    address lender,
    address token
  )
    external pure
    returns(bytes32)
  {
    return _computePositionId(loan, lender, token);
  }

  function _computePositionId(
    address loan,
    address lender,
    address token
  )
    internal pure
    returns(bytes32)
  {
    return keccak256(abi.encode(loan, lender, token));
  }


    function getOutstandingDebt(
      ILineOfCredit.Credit memory credit,
      bytes32 id,
      address oracle,
      address interestRate
    )
      external
      returns (ILineOfCredit.Credit memory c, uint256 principal, uint256 interest)
    {
        c = _accrue(credit, id, IInterestRateCredit(interestRate)); // Issue is accruing interest from here

        int256 price = IOracle(oracle).getLatestAnswer(c.token);

        principal += _calculateValue(
            price,
            c.principal,
            c.decimals
        );
        interest += _calculateValue(
            price,
            c.interestAccrued,
            c.decimals
        );

        return (c, principal, interest);
  }

   /**
     * @notice         - Gets total valuation for amount of tokens using given oracle. 
     * @dev            - Assumes oracles all return answers in USD with 1e8 decimals
                       - Does not check if price < 0. HAndled in Oracle or Loan
     * @param oracle   - oracle contract specified by loan getting valuation
     * @param token    - token to value on oracle
     * @param amount   - token amount
     * @param decimals - token decimals
     * @return         - total value in usd of all tokens 
     */
    function getValuation(
      IOracle oracle,
      address token,
      uint256 amount,
      uint8 decimals
    )
      external
      returns(uint256)
    {
      return _calculateValue(oracle.getLatestAnswer(token), amount, decimals);
    }

    /**
     * @notice
     * @dev            - Assumes oracles all return answers in USD with 1e8 decimals
                       - Does not check if price < 0. HAndled in Oracle or Loan
     * @param price    - oracle price of asset. 8 decimals
     * @param amount   - amount of tokens vbeing valued.
     * @param decimals - token decimals to remove for usd price
     * @return         - total USD value of amount in 8 decimals 
     */
    function calculateValue(
      int price,
      uint256 amount,
      uint8 decimals
    )
      internal pure
      returns(uint256)
    {
      return _calculateValue(price, amount, decimals);
    }


      /**
     * @notice         - calculates value of tokens and denominates in USD 8
     * @dev            - Assumes all oracles return USD responses in 1e8 decimals
     * @param price    - oracle price of asset. 8 decimals
     * @param amount   - amount of tokens vbeing valued.
     * @param decimals - token decimals to remove for usd price
     * @return         - total value in usd of all tokens 
     */
    function _calculateValue(
      int price,
      uint256 amount,
      uint8 decimals
    )
      internal pure
      returns(uint256)
    {
      return price <= 0 ? 0 : (amount * uint(price)) / (1 * 10 ** decimals);
    }

  

  function create(
      bytes32 id,
      uint256 amount,
      address lender,
      address token,
      address oracle
  )
      external 
      returns(ILineOfCredit.Credit memory credit)
  {
      return _create(id, amount, lender, token, oracle);
  }

  function _create(
      bytes32 id,
      uint256 amount,
      address lender,
      address token,
      address oracle
  )
      internal 
      returns(ILineOfCredit.Credit memory credit)
  {
      int price = IOracle(oracle).getLatestAnswer(token);
      if(price <= 0 ) { revert NoTokenPrice(); }

      (bool passed, bytes memory result) = token.call(
          abi.encodeWithSignature("decimals()")
      );
      uint8 decimals = !passed ? 18 : abi.decode(result, (uint8));

      credit = ILineOfCredit.Credit({
          lender: lender,
          token: token,
          decimals: decimals,
          deposit: amount,
          principal: 0,
          interestAccrued: 0,
          interestRepaid: 0
      });

      emit AddCredit(lender, token, amount, id);

      return credit;
  }

  function repay(
    ILineOfCredit.Credit memory credit,
    bytes32 id,
    uint256 amount
  )
    external
    // TODO don't need to return all uints if we can get events working in library to show up on subgraph
    returns (ILineOfCredit.Credit memory)
  { unchecked {
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
  } }

  function withdraw(
    ILineOfCredit.Credit memory credit,
    bytes32 id,
    uint256 amount
  )
    external
    returns (ILineOfCredit.Credit memory)
  { unchecked {
      if(amount > credit.deposit - credit.principal + credit.interestRepaid) {
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
  } }


  function accrue(
    ILineOfCredit.Credit memory credit,
    bytes32 id,
    address interest
  )
    external
    returns (ILineOfCredit.Credit memory)
  { 
    return _accrue(credit, id, IInterestRateCredit(interest));
  }

  function _accrue(
    ILineOfCredit.Credit memory credit,
    bytes32 id,
    IInterestRateCredit interest
  )
    internal
    returns (ILineOfCredit.Credit memory)
  { unchecked {
      // interest will almost always be less than deposit
      // low risk of overflow unless extremely high interest rate

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
  } }
}
