pragma solidity 0.8.9;

import {LineLib} from "../utils/LineLib.sol";
import {IOracle} from "../interfaces/IOracle.sol";

interface ILineOfCredit {
    // Lender data
    struct Credit {
        //  all denominated in token, not USD
        uint256 deposit; // The total liquidity provided by a Lender in a given token on a Line of Credit
        uint256 principal; // The amount of a Lender's Deposit on a Line of Credit that has actually been drawn down by the Borrower (USD)
        uint256 interestAccrued; // Interest due by a Borrower but not yet repaid to the Line of Credit contract
        uint256 interestRepaid; // Interest repaid by a Borrower to the Line of Credit contract but not yet withdrawn by a Lender
        uint8 decimals; // Decimals of Credit Token for calcs
        address token; // The token being lent out (Credit Token)
        address lender; // The person to repay
    }
    // General Events

    event UpdateStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph

    event DeployLine(address indexed oracle, address indexed arbiter, address indexed borrower);

    // MutualConsent borrower/lender events

    event AddCredit(address indexed lender, address indexed token, uint256 indexed deposit, bytes32 id);
    // can only reference id once AddCredit is emitted because it will be indexed offchain

    event SetRates(bytes32 indexed id, uint128 indexed dRate, uint128 indexed fRate);

    event IncreaseCredit(bytes32 indexed id, uint256 indexed deposit);

    // Lender Events

    // Emits data re Lender removes funds (principal) - there is no corresponding function, just withdraw()
    event WithdrawDeposit(bytes32 indexed id, uint256 indexed amount);

    // Emits data re Lender withdraws interest - there is no corresponding function, just withdraw()
    event WithdrawProfit(bytes32 indexed id, uint256 indexed amount);

    // Emitted when any credit line is closed by the line's borrower or the position's lender
    event CloseCreditPosition(bytes32 indexed id);

    // After accrueInterest runs, emits the amount of interest added to a Borrower's outstanding balance of interest due
    // but not yet repaid to the Line of Credit contract
    event InterestAccrued(bytes32 indexed id, uint256 indexed amount);

    // Borrower Events

    // receive full line or drawdown on credit
    event Borrow(bytes32 indexed id, uint256 indexed amount);

    // Emits that a Borrower has repaid an amount of interest Results in an increase in interestRepaid, i.e. interest not yet withdrawn by a Lender). There is no corresponding function
    event RepayInterest(bytes32 indexed id, uint256 indexed amount);

    // Emits that a Borrower has repaid an amount of principal - there is no corresponding function
    event RepayPrincipal(bytes32 indexed id, uint256 indexed amount);

    event Default(bytes32 indexed id);

    // Access Errors
    error NotActive();
    error NotBorrowing();
    error CallerAccessDenied();

    // Tokens
    error TokenTransferFailed();
    error NoTokenPrice();

    // Line
    error BadModule(address module);
    error NoLiquidity();
    error PositionExists();
    error CloseFailedWithPrincipal();
    error NotInsolvent(address module);
    error NotLiquidatable();
    error AlreadyInitialized();

    function init() external returns (LineLib.STATUS);

    // MutualConsent functions
    function addCredit(uint128 drate, uint128 frate, uint256 amount, address token, address lender)
        external
        payable
        returns (bytes32);
    function setRates(bytes32 id, uint128 drate, uint128 frate) external returns (bool);
    function increaseCredit(bytes32 id, uint256 amount) external payable returns (bool);

    // Borrower functions
    function borrow(bytes32 id, uint256 amount) external returns (bool);
    function depositAndRepay(uint256 amount) external payable returns (bool);
    function depositAndClose() external payable returns (bool);
    function close(bytes32 id) external payable returns (bool);

    // Lender functions
    function withdraw(bytes32 id, uint256 amount) external returns (bool);

    // Arbiter functions
    function declareInsolvent() external returns (bool);

    function accrueInterest() external returns (bool);
    function healthcheck() external returns (LineLib.STATUS);
    function updateOutstandingDebt() external returns (uint256, uint256);

    function status() external returns (LineLib.STATUS);
    function borrower() external returns (address);
    function arbiter() external returns (address);
    function oracle() external returns (IOracle);
    function counts() external view returns (uint256, uint256);
}
