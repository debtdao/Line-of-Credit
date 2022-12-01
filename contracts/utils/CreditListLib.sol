pragma solidity 0.8.9;

import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {CreditLib} from "./CreditLib.sol";

/**
 * @title Debt DAO Line of Credit Library
 * @author Kiba Gateaux
 * @notice Core logic and variables to be reused across all Debt DAO Marketplace Line of Credit contracts
 */

library CreditListLib {
    /**
     * @dev assumes that `id` of a single credit line within the Line of Credit facility (same lender/token) is stored only once in the `positions` array
     *  since there's no reason for them to be stored multiple times.
     * This means cleanup on _close() and checks on addCredit() are CRITICAL. If `id` is duplicated then the position can't be closed
     * @param ids - all current credit lines on the Line of Credit facility
     * @param id - the hash id of the credit line to be removed from active ids after removePosition() has run
     * @return newPositions - all active credit lines on the Line of Credit facility after the `id` has been removed [Bob - consider renaming to newIds
     * Bob - consider renaming this function removeId()
     */
    function removePosition(bytes32[] storage ids, bytes32 id) external returns (bool) {
        uint256 len = ids.length;

        for (uint256 i; i < len; ++i) {
            if (ids[i] == id) {
                delete ids[i];
                return true;
            }
        }

        return true;
    }

    /**
     * @notice - removes the individual credit line id from the head of the repayment queue and puts it at end of queue
     *         - moves 2nd in queue to first position in queue
     * @param ids - all current credit lines on the Line of Credit facility
     * @return newPositions - remaining credit lines after moving first to last in array
     */
    function stepQ(bytes32[] storage ids) external returns (bool) {
        uint256 len = ids.length;
        if (len <= 1) return true; // already ordered

        bytes32 last = ids[0];

        if (len == 2) {
            ids[0] = ids[1];
            ids[1] = last;
        } else {
            // move all existing ids up in the queue
            for (uint256 i = 1; i < len; ++i) {
                ids[i - 1] = ids[i]; // could also clean arr here like in _SortIntoQ
            }
            // cycle first id back to end of queue
            ids[len - 1] = last;
        }

        return true;
    }
}
