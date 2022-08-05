pragma solidity 0.8.9;
import { ILineOfCredit } from "../interfaces/ILineOfCredit.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { CreditLib } from "./CreditLib.sol";
/**
  * @title Debt DAO P2P Loan Library
  * @author Kiba Gateaux
  * @notice Core logic and variables to be reused across all Debt DAO Marketplace loans
 */
library CreditListLib {
      using CreditLib for ILineOfCredit.Credit;

    // function getOutstandingDebt(
    //   ILineOfCredit.Credit[] storage self,
    //   IOracle oracle
    // )
    //   external
    //   returns (uint256 principal, uint256 interest)
    // {
    //     uint256 len = self.length;
    //     if (len == 0) return (0, 0);

    //     ILineOfCredit.Credit memory credit;
    //     for (uint256 i = 0; i < len; i++) {
    //         bytes32 id = self[i];
    //         _accrueInterest(id); // Issue is accruing interest from here
    //         credit = credits[id];

    //         int256 price = oracle.getLatestAnswer(credit.token);

    //         principal += _calculateValue(
    //             price,
    //             credit.principal,
    //             credit.decimals
    //         );
    //         interest += _calculateValue(
    //             price,
    //             credit.interestAccrued,
    //             credit.decimals
    //         );
    //     }
    // }

    /**
     * @dev assumes that `id` is stored only once in `positions` array bc no reason for Loans to store multiple times.
          This means cleanup on _close() and checks on addDebtPosition are CRITICAL. If `id` is duplicated then the position can't be closed
     * @param ids - all current active positions on the loan
     * @param id - hash id that must be removed from active positions
     * @return newPositions - all active positions on loan after `id` is removed
     */
    function removePosition(bytes32[] storage ids, bytes32 id) external pure returns(bool) {
      uint256 len = ids.length;
      uint256 count = 0;

      for(uint i = 0; i < len; i++) {
          if(ids[i] != id) {
              ids[count] = ids[i];
              count++;
          }
      }

      return true;
    }

    /**
     * @notice - removes debt position from head of repayement queue and puts it at end of line
     *         - moves 2nd in line to first
     * @param ids - all current active positions on the loan
     * @return newPositions - positions after moving first to last in array
     */
    function stepQ(bytes32[] storage ids) external pure returns(bool) {
      uint256 len = ids.length ;
      if(len <= 1) return true; // already ordered

      bytes32 last = ids[0];
      
      if(len == 2) {
        ids[0] = ids[1];
        ids[1] = last;
      } else {
        // move all existing ids up in line
        for(uint i = 1; i < len; i++) {
          ids[i - 1] = ids[i];
        }
        // cycle first el back to end of queue
        ids[len - 1] = last;
      }
      
      return true;
    }
}
