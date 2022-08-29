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
    /**
     * @dev assumes that `id` is stored only once in `positions` array bc no reason for Loans to store multiple times.
          This means cleanup on _close() and checks on addDebtPosition are CRITICAL. If `id` is duplicated then the position can't be closed
     * @param ids - all current active positions on the loan
     * @param id - hash id that must be removed from active positions
     * @return newPositions - all active positions on loan after `id` is removed
     */
    function removePosition(bytes32[] storage ids, bytes32 id) external returns(bool) {
      uint256 len = ids.length;

      for(uint256 i; i < len;) {
          if(ids[i] == id) {
              delete ids[i];
              return true;
          }
          unchecked { ++i; }
      }

      return true;
    }

    /**
     * @notice - removes debt position from head of repayement queue and puts it at end of line
     *         - moves 2nd in line to first
     * @param ids - all current active positions on the loan
     * @return newPositions - positions after moving first to last in array
     */
    function stepQ(bytes32[] storage ids) external returns(bool) {
      uint256 len = ids.length ;
      if(len <= 1) return true; // already ordered

      bytes32 last = ids[0];
      
      if(len == 2) {
        ids[0] = ids[1];
        ids[1] = last;
      } else {
        // move all existing ids up in line
        for(uint i = 1; i < len;) {
          ids[i - 1] = ids[i]; // could also clean arr here like in _SoritIntoQ
          unchecked {  ++i; }
        }
        // cycle first el back to end of queue
        ids[len - 1] = last;
      }
      
      return true;
    }
}
