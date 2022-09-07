pragma solidity 0.8.9;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IInterestRateCredit} from "../interfaces/IInterestRateCredit.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {LineLib} from "./LineLib.sol";

/**
 * @title Debt DAO P2P Line Library
 * @author Kiba Gateaux
 * @notice Core logic and variables to be reused across all Debt DAO Marketplace lines
 */
library CreditLib {
    event AddCredit(address indexed lender, address indexed token, uint256 indexed deposit, bytes32 positionId);

    event WithdrawDeposit(bytes32 indexed id, uint256 indexed amount);
    // lender removing funds from Line  principal
    event WithdrawProfit(bytes32 indexed id, uint256 indexed amount);
    // lender taking interest earned out of contract

    event InterestAccrued(bytes32 indexed id, uint256 indexed amount);
    // interest added to borrowers outstanding balance

    // Borrower Events

    event Borrow(bytes32 indexed id, uint256 indexed amount);
    // receive full line or drawdown on credit

    event RepayInterest(bytes32 indexed id, uint256 indexed amount);

    event RepayPrincipal(bytes32 indexed id, uint256 indexed amount);

    error NoTokenPrice();

    error PositionExists();

    /**
     * @dev          - Create deterministic hash id for a debt position on `line` given position details
     * @param line   - line that debt position exists on
     * @param lender - address managing debt position
     * @param token  - token that is being lent out in debt position
     * @return positionId
     */
    function computeId(address line, address lender, address token) external pure returns (bytes32) {
        return keccak256(abi.encode(line, lender, token));
    }

    function getOutstandingDebt(ILineOfCredit.Credit memory credit, bytes32 id, address oracle, address interestRate)
        external
        returns (ILineOfCredit.Credit memory c, uint256 principal, uint256 interest)
    {
        c = accrue(credit, id, interestRate);

        int256 price = IOracle(oracle).getLatestAnswer(c.token);

        principal = calculateValue(price, c.principal, c.decimals);
        interest = calculateValue(price, c.interestAccrued, c.decimals);

        return (c, principal, interest);
    }
    /**
     * @notice         - calculates value of tokens in US
     * @dev            - Assumes oracles all return answers in USD with 1e8 decimals
     * - Does not check if price < 0. HAndled in Oracle or Line
     * @param price    - oracle price of asset. 8 decimals
     * @param amount   - amount of tokens vbeing valued.
     * @param decimals - token decimals to remove for usd price
     * @return         - total USD value of amount in 8 decimals
     */

    function calculateValue(int256 price, uint256 amount, uint8 decimals) public pure returns (uint256) {
        return price <= 0 ? 0 : (amount * uint256(price)) / (1 * 10 ** decimals);
    }

    function create(bytes32 id, uint256 amount, address lender, address token, address oracle)
        external
        returns (ILineOfCredit.Credit memory credit)
    {
        int256 price = IOracle(oracle).getLatestAnswer(token);
        if (price <= 0) {
            revert NoTokenPrice();
        }

        uint8 decimals;
        if (token == Denominations.ETH) {
            decimals = 18;
        } else {
            (bool passed, bytes memory result) = token.call(abi.encodeWithSignature("decimals()"));
            decimals = !passed ? 18 : abi.decode(result, (uint8));
        }

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

    function repay(ILineOfCredit.Credit memory credit, bytes32 id, uint256 amount)
        external
        returns (ILineOfCredit.Credit memory)
    {
        unchecked {
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
    }

    function withdraw(ILineOfCredit.Credit memory credit, bytes32 id, uint256 amount)
        external
        returns (ILineOfCredit.Credit memory)
    {
        unchecked {
            if (amount > credit.deposit - credit.principal + credit.interestRepaid) {
                revert ILineOfCredit.NoLiquidity();
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
    }

    function accrue(ILineOfCredit.Credit memory credit, bytes32 id, address interest)
        public
        returns (ILineOfCredit.Credit memory)
    {
        unchecked {
            // interest will almost always be less than deposit
            // low risk of overflow unless extremely high interest rate

            // get token demoninated interest accrued
            uint256 accruedToken = IInterestRateCredit(interest).accrueInterest(id, credit.principal, credit.deposit);

            // update credits balance
            credit.interestAccrued += accruedToken;

            emit InterestAccrued(id, accruedToken);
            return credit;
        }
    }
}
