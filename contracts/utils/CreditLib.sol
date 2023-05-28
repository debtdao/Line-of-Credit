pragma solidity 0.8.16;
import {Denominations} from "chainlink/Denominations.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IFixedInterestRateCalculator} from "../interfaces/IFixedInterestRateCalculator.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {LineLib} from "./LineLib.sol";

// Lender data
struct Credit {
    //  all denominated in token, not USD
    uint256 deposit; // The total liquidity provided by a Lender in a given token on a Line of Credit
    uint256 principal; // The amount of a Lender's Deposit on a Line of Credit that has actually been drawn down by the Borrower (in Tokens)
    uint256 interestAccrued; // Interest due by a Borrower but not yet repaid to the Line of Credit contract
    uint256 interestRepaid; // Interest repaid by a Borrower to the Line of Credit contract but not yet withdrawn by a Lender
    uint8 decimals; // Decimals of Credit Token for calcs
    address token; // The token being lent out (Credit Token)
    address lender; // The person to repay
    bool isOpen; // Status of position
}

/**
 * @title Debt DAO Line of Credit Library
 * @author Kiba Gateaux
 * @notice Core logic and variables to be reused across all Debt DAO Marketplace Line of Credit contracts
 */
library CreditLib {
    event AddCredit(address indexed lender, address indexed token, uint256 indexed deposit, bytes32 id);

    /// @notice Emitted when Lender withdraws from their initial deposit
    event WithdrawDeposit(bytes32 indexed id, uint256 indexed amount);

    /// @notice Emitted when Lender withdraws interest paid by borrower
    event WithdrawProfit(bytes32 indexed id, uint256 indexed amount);

    /// @notice Emits amount of interest (denominated in credit token) added to a Borrower's outstanding balance
    event InterestAccrued(bytes32 indexed id, uint256 indexed amount);

    // Borrower Events

    /// @notice Emits when Borrower has drawn down an amount (denominated in credit.token) on a credit line
    event Borrow(bytes32 indexed id, uint256 indexed amount);

    /// @notice Emits that a Borrower has repaid some amount of interest (denominated in credit.token)
    event RepayInterest(bytes32 indexed id, uint256 indexed amount);

    /// @notice Emits that a Borrower has repaid some amount of principal (denominated in credit.token)
    event RepayPrincipal(bytes32 indexed id, uint256 indexed amount);

    // Errors

    error NoTokenPrice();

    error PositionExists();

    error RepayAmountExceedsDebt(uint256 totalAvailable);

    error InvalidTokenDecimals();

    error NoQueue();

    error PositionIsClosed();

    error NoLiquidity();

    error CloseFailedWithPrincipal();

    error CallerAccessDenied();

    /**
     * @dev          - Creates a deterministic hash id for a credit line provided by a single Lender for a given token on a Line of Credit facility
     * @param line   - The Line of Credit facility concerned
     * @param lender - The address managing the credit line concerned
     * @param token  - The token being lent out on the credit line concerned
     * @return id
     */
    function computeId(address line, address lender, address token) external pure returns (bytes32) {
        return keccak256(abi.encode(line, lender, token));
    }

    // getOutstandingDebt() is called by updateOutstandingDebt()
    function getOutstandingDebt(
        Credit memory credit,
        bytes32 id,
        address oracle,
        address interestRate
    ) external returns (Credit memory c, uint256 principal, uint256 interest) {
        c = accrue(credit, id, interestRate);

        int256 price = IOracle(oracle).getLatestAnswer(c.token);

        principal = calculateValue(price, c.principal, c.decimals);
        interest = calculateValue(price, c.interestAccrued, c.decimals);

        return (c, principal, interest);
    }

    /**
     * @notice         - Calculates value of tokens.  Used for calculating the USD value of principal and of interest during getOutstandingDebt()
     * @dev            - Assumes Oracle returns answers in USD with 1e8 decimals
     *                 - If price < 0 then we treat it as 0.
     * @param price    - The Oracle price of the asset. 8 decimals
     * @param amount   - The amount of tokens being valued.
     * @param decimals - Token decimals to remove for USD price
     * @return         - The total USD value of the amount of tokens being valued in 8 decimals
     */
    function calculateValue(int price, uint256 amount, uint8 decimals) public pure returns (uint256) {
        return price <= 0 ? 0 : (amount * uint(price)) / (1 * 10 ** decimals);
    }

    /**
     * see ILineOfCredit._createCredit
     * @notice called by LineOfCredit._createCredit during every repayment function
     */
    function create(
        bytes32 id,
        uint256 amount,
        address lender,
        address token
    ) external returns (Credit memory credit) {
        (bool passed, bytes memory result) = token.call(abi.encodeWithSignature("decimals()"));

        if (!passed || result.length == 0) {
            revert InvalidTokenDecimals();
        }

        uint8 decimals = abi.decode(result, (uint8));

        credit = Credit({
            lender: lender,
            token: token,
            decimals: decimals,
            deposit: amount,
            principal: 0,
            interestAccrued: 0,
            interestRepaid: 0,
            isOpen: true
        });

        emit AddCredit(lender, token, amount, id);

        return credit;
    }

    /**
     * see ILineOfCredit._repay
     * @notice called by LineOfCredit._repay during every repayment function
     * @dev uses uncheckd math. assumes checks have been done in caller
     * @param credit - The lender position being repaid
     */
    function repay(
        Credit memory credit,
        bytes32 id,
        uint256 amount,
        address payer
    ) external returns (Credit memory) {
        if (!credit.isOpen) {
            revert PositionIsClosed();
        }

        unchecked {
            if (amount > credit.principal + credit.interestAccrued) {
                revert RepayAmountExceedsDebt(credit.principal + credit.interestAccrued);
            }

            if (amount <= credit.interestAccrued) {
                credit.interestAccrued -= amount;
                credit.interestRepaid += amount;
                emit RepayInterest(id, amount);
            } else {
                uint256 interest = credit.interestAccrued;
                uint256 principalPayment = amount - interest;

                // update individual credit line denominated in token
                credit.principal -= principalPayment;
                credit.interestRepaid += interest;
                credit.interestAccrued = 0;

                emit RepayInterest(id, interest);
                emit RepayPrincipal(id, principalPayment);
            }
        }

        // if we arent using funds from reserves to repay then pull tokens from target
        if(payer != address(0)) {
            LineLib.receiveTokenOrETH(credit.token, payer, amount);
        }

        return credit;
    }

    /**
     * see ILineOfCredit.withdraw
     * @notice called by LineOfCredit.withdraw during every repayment function
     * @dev uses uncheckd math. assumes checks have been done in caller
     * @param credit - The lender position that is being bwithdrawn from
     */
    function withdraw(
        Credit memory credit,
        bytes32 id,
        address caller,
        uint256 amount
    ) external returns (Credit memory) {
        if (caller != credit.lender) {
            revert CallerAccessDenied();
        }

        unchecked {
            if (amount > credit.deposit - credit.principal + credit.interestRepaid) {
                revert ILineOfCredit.NoLiquidity();
            }

            if (amount > credit.interestRepaid) {
                uint256 interest = credit.interestRepaid;

                credit.deposit -= amount - interest;
                credit.interestRepaid = 0;

                // emit events before setting to 0
                emit WithdrawDeposit(id, amount - interest);
                emit WithdrawProfit(id, interest);
            } else {
                credit.interestRepaid -= amount;
                emit WithdrawProfit(id, amount);
            }
        }

        LineLib.sendOutTokenOrETH(credit.token, credit.lender, amount);

        return credit;
    }

    /**
     * see ILineOfCredit._accrue
     * @notice called by LineOfCredit._accrue during every repayment function
     * @dev public to use in `getOutstandingDebt`
     * @param interest - interset rate contract used by line that will calculate interest owed
     */
    function accrue(
        Credit memory credit,
        bytes32 id,
        address interest
    ) public returns (Credit memory) {
        if (!credit.isOpen) {
            return credit;
        }
        unchecked {
            // interest will almost always be less than deposit
            // low risk of overflow unless extremely high interest rate

            // get token demoninated interest accrued
            uint256 accruedToken = IFixedInterestRateCalculator(interest).accrueInterest(id, credit.principal, credit.deposit);

            // update credit line balance
            credit.interestAccrued += accruedToken;

            emit InterestAccrued(id, accruedToken);
            return credit;
        }
    }

    function interestAccrued(
        Credit memory credit,
        bytes32 id,
        address interest
    ) external view returns (uint256) {
        return
            credit.interestAccrued +
            IFixedInterestRateCalculator(interest).getInterestAccrued(id, credit.principal, credit.deposit);
    }

    function getNextRateInQ(uint256 principal, bytes32 id, address interest) external view returns (uint128, uint128) {
        if (principal == 0) {
            revert NoQueue();
        } else {
            return IFixedInterestRateCalculator(interest).getRates(id);
        }
    }
}
