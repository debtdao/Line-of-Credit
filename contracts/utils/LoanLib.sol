pragma solidity 0.8.9;
import { ILoan } from "../interfaces/ILoan.sol";
import { IOracle } from "../interfaces/IOracle.sol";
/**
  * @title Debt DAO P2P Loan Library
  * @author Kiba Gateaux
  * @notice Core logic and variables to be reused across all Debt DAO Marketplace loans
 */
library LoanLib is ILoan {
    address constant DEBT_TOKEN = address(0xdebf);

    enum STATUS {
        // ¿hoo dis
        // Loan has been deployed but terms and conditions are still being signed off by parties
        UNINITIALIZED,
        INITIALIZED,

        // ITS ALLLIIIIVVEEE
        // Loan is operational and actively monitoring status
        ACTIVE,
        UNDERCOLLATERALIZED,
        LIQUIDATABLE, // [#X
        DELINQUENT,

        // Loan is in distress and paused
        LIQUIDATING,
        OVERDRAWN,
        DEFAULT,
        ARBITRATION,

        // Lön izz ded
        // Loan is no longer active, successfully repaid or insolvent
        REPAID,
        INSOLVENT
    }

    function updateStatus(STATUS status, STATUS target) returns(STATUS) {
        STATUS s = status;          // gas savings
        if (s == target) return s;  // check if it needs updating
        status = target;            // set storage in Line contract
        emit UpdateLoanStatus(uint256(s));
        return s;
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
      internal
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


    /**
     * @dev          - Create deterministic hash id for a debt position on `loan` given position details
     * @param loan   - loan that debt position exists on
     * @param lender - address managing debt position
     * @param token  - token that is being lent out in debt position
     * @return positionId
     */
    function computePositionId(address loan, address lender, address token) external pure returns(bytes32) {
      return keccak256(abi.encode(loan, lender, token));
    }


}
