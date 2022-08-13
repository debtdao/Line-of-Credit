pragma solidity 0.8.9;
import { IOracle } from "../interfaces/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";

/**
  * @title Debt DAO P2P Loan Library
  * @author Kiba Gateaux
  * @notice Core logic and variables to be reused across all Debt DAO Marketplace loans
 */
library LoanLib {
    using SafeERC20 for IERC20;

    error TransferFailed();
    error BadToken();

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

    /**
     * @dev `id` MUST be in `positions` array ONLY ONCE.
          This means cleanup on _close() and checks on addCredit are CRITICAL. If `id` is duplicated then the position can't be closed
     * @param positions - all current active positions on the loan
     * @param id - hash id that must be removed from active positions
     * @return newPositions - all active positions on loan after `id` is removed
     */
    function removePosition(bytes32[] calldata positions, bytes32 id) external pure returns(bytes32[] memory) {
      uint256 len = positions.length - 1;
      uint256 count = 0;
      bytes32[] memory newPositions = new bytes32[](len);

      for(uint i = 0; i <= len; i++) {
          if(positions[i] != id) {
              newPositions[count] = positions[i];
              count++;
          }
      }

      return newPositions;
    }

    /**
     * @notice - removes debt position from head of repayement queue and puts it at end of line
     *         - moves 2nd in line to first
     * @param positions - all current active positions on the loan
     * @return newPositions - positions after moving first to last in array
     */
    function stepQ(bytes32[] calldata positions) external pure returns(bytes32[] memory) {
      uint256 len = positions.length ;
      if(len <= 1) return positions; // already ordered

      bytes32[] memory newPositions = new bytes32[](len);
      
      if(len == 2) {
        newPositions[0] = positions[1];
        newPositions[1] = positions[0];
        return newPositions;
      }
      
      // move all existing positions up in line
      for(uint i = 1; i < len; i++) {
        newPositions[i - 1] = positions[i];
      }
      // cycle first el back to end of queue
      newPositions[len - 1] = positions[0];

      return newPositions;
    }

    /**
     * @notice - Send ETH or ERC20 token from this contract to an external contract
     * @param token - address of token to send out. Denominations.ETH for raw ETH
     * @param receiver - address to send tokens to
     * @param amount - amount of tokens to send
     */
    function sendOutTokenOrETH(
      address token,
      address receiver,
      uint256 amount
    )
      external
      returns (bool)
    {
        if(token == address(0)) { revert TransferFailed(); }
        if(token!= Denominations.ETH) { // ERC20
            IERC20(token).safeTransfer(receiver, amount);
        } else { // ETH
            payable(receiver).transfer(amount);
        }
        return true;
    }

    /**
     * @notice - Send ETH or ERC20 token from this contract to an external contract
     * @param token - address of token to send out. Denominations.ETH for raw ETH
     * @param sender - address that is giving us tokens/ETH
     * @param amount - amount of tokens to send
     */
    function receiveTokenOrETH(
      address token,
      address sender,
      uint256 amount
    )
      external
      returns (bool)
    {
        if(token == address(0)) { revert TransferFailed(); }
        if(token!= Denominations.ETH) { // ERC20
            IERC20(token).safeTransferFrom(sender, address(this), amount);
        } else { // ETH
            if(msg.value < amount) { revert TransferFailed(); }
        }
        return true;
    }

    /**
     * @notice - Helper function to get current balance of this contract for ERC20 or ETH
     * @param token - address of token to check. Denominations.ETH for raw ETH
    */
    function getBalance(address token) external view returns (uint256) {
        if(token == address(0)) return 0;
        return token != Denominations.ETH ?
            IERC20(token).balanceOf(address(this)) :
            address(this).balance;
    }

}
