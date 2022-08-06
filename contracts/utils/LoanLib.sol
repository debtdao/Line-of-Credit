pragma solidity 0.8.9;
import { ILoan } from "../interfaces/ILoan.sol";
import { IOracle } from "../interfaces/IOracle.sol";
/**
  * @title Debt DAO P2P Loan Library
  * @author Kiba Gateaux
  * @notice Core logic and variables to be reused across all Debt DAO Marketplace loans
 */
library LoanLib {
    event UpdateLoanStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph

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

    function updateStatus(STATUS status, STATUS target) external returns(STATUS) {
        if (status == target) return status;  // check if it needs updating
        status = target;            // set storage in Line contract
        emit UpdateLoanStatus(uint256(status));
        return status;
    }
}
