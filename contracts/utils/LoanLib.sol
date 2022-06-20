pragma solidity 0.8.9;
import { IOracle } from "../interfaces/IOracle.sol";
/**
 * @title Debt DAO P2P Loan Library
 * @author Kiba Gateaux
 * @notice Core logic and variables to be reused across all Debt DAO Marketplace loans
 */
library LoanLib {
    address constant DEBT_TOKEN = address(0xdebf);

    enum STATUS {
        // ¿hoo dis
        // Loan has been deployed but terms and conditions are still being signed off by parties
        UNINITIALIZED, // [#X]
        INITIALIZED, // [#X]

        // ITS ALLLIIIIVVEEE
        // Loan is operational and actively monitoring status
        ACTIVE, // [#X]
        UNDERCOLLATERALIZED, // [#X]
        LIQUIDATABLE, // [#X
        DELINQUENT, // [#X]

        // Loan is in distress and paused
        LIQUIDATING, // [#X]
        OVERDRAWN, // [#X]
        DEFAULT, // [#X]
        ARBITRATION, // [#X]

        // Lön izz ded
        // Loan is no longer active, successfully repaid or insolvent
        REPAID, // [#X]
        INSOLVENT // [#X]
    }

    /**
      @notice
      @dev - Assumes oracles all return answers in USD with 1e8 decimals
           - Does not check if price < 0. HAndled in Oracle or Loan
      @param oracle - oracle contract specified by loan getting valuation
      @param token - token to value on oracle
      @param amount - token amount
      @param decimals - token decimals
      @return total value in usd of all tokens 

     */
    function getValuation(
      IOracle oracle,
      address token,
      uint256 amount,
      uint8 decimals
    )
      external view
      returns(uint256)
    {
      int prc = oracle.getLatestAnswer(token);
      return prc == 0 ? 0 : (amount * prc) / (1 * 10 ** decimals);
    }


    /**
      @dev Create deterministic hash id for a debt position on `loan` given position details
      @param loan - loan that debt position exists on
      @param lender - address managing debt position
      @param token - token that is being lent out in debt position
      @return positionId

     */
    function computePositionId(address loan, address lender, address token) external pure returns(bytes32) {
      return keccak256(abi.encode(loan, lender, token));
    }

    /**
      @dev assumes that `id` is stored only once in `positions` array bc no reason for Loans to store multiple times.
          This means cleanup on _close() and checks on addDebtPosition are CRITICAL. If `id` is duplicated then the position can't be closed
      @param positions - all current active positions on the loan
      @param id - hash id that must be removed from active positions
      @return newPositions - all active positions on loan after `id` is removed

     */
    function removePosition(bytes32[] calldata positions, bytes32 id) external view returns(bytes32[] memory) {
      uint256 newLength = positions.length - 1;
      uint256 count = 0;
      bytes32[] memory newPositions = new bytes32[](newLength);

      for(uint i = 0; i < positions.length; i++) {
          if(positions[i] != id) {
              newPositions[count] = positions[i];
              count++;
          }
      }

      return newPositions;
    }
}
