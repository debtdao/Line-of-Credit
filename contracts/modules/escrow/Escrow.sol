pragma solidity 0.8.9;

import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEscrow} from "../../interfaces/IEscrow.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";
import {CreditLib} from "../../utils/CreditLib.sol";
import {LineLib} from "../../utils/LineLib.sol";
import {EscrowState, EscrowLib} from "../../utils/EscrowLib.sol";

contract Escrow is IEscrow {
    using SafeERC20 for IERC20;
    using EscrowLib for EscrowState;

    // the minimum value of the collateral in relation to the outstanding debt e.g. 10% of outstanding debt
    uint256 public immutable minimumCollateralRatio;

    // Stakeholders and contracts used in Escrow
    address public immutable oracle;
    address public immutable borrower;
    
    EscrowState private state;

    constructor(
        uint256 _minimumCollateralRatio,
        address _oracle,
        address _line,
        address _borrower
    ) {
        minimumCollateralRatio = _minimumCollateralRatio;
        oracle = _oracle;
        borrower = _borrower;
        state.line = _line;
    }

    function line() external view override returns(address) {
      return state.getLine();
    }

    function isLiquidatable() external returns(bool) {
        return _getLatestCollateralRatio() < minimumCollateralRatio;
    }

    function deposited(address token)
        external
        view
        returns (Deposit memory)
    {
        return state.getDeposited(token);
    }

    function updateLine(address _line) external returns(bool) {
      return state.updateLine(_line);
    }

    /**
     * @notice add collateral to your position
     * @dev updates cratio
     * @dev requires that the token deposited can be valued by the escrow's oracle & the depositor has approved this contract
     * @dev - callable by anyone
     * @param amount - the amount of collateral to add
     * @param token - the token address of the deposited token
     * @return - the updated cratio
     */
    function addCollateral(uint256 amount, address token)
        external
        returns (uint256)
    {
        require(amount > 0);
        if (!state.enabled[token]) {
            revert InvalidCollateral();
        }

        LineLib.receiveTokenOrETH(token, msg.sender, amount);

        state.deposited[token].amount += amount;

        emit AddCollateral(token, amount);

        return _getLatestCollateralRatio();
    }

    function enableCollateral(address token) external returns (bool) {
        return state.enableCollateral(token, oracle);
    }

    /**
     * @notice remove collateral from your position. Must remain above min collateral ratio
     * @dev callable by `borrower`
     * @dev updates cratio
     * @param amount - the amount of collateral to release
     * @param token - the token address to withdraw
     * @param to - who should receive the funds
     * @return - the updated cratio
     */
    function releaseCollateral(
        uint256 amount,
        address token,
        address to
    ) external returns (uint256) {
        require(amount > 0);
        if (msg.sender != borrower) {
            revert CallerAccessDenied();
        }
        if (state.deposited[token].amount < amount) {
            revert InvalidCollateral();
        }
        state.deposited[token].amount -= amount;

        LineLib.sendOutTokenOrETH(token, to, amount);

        uint256 cratio = _getLatestCollateralRatio();
        // fail if reduces cratio below min
        // but allow borrower to always withdraw if fully repaid
        if (
            cratio < minimumCollateralRatio && // if undercollateralized, revert;
            ILineOfCredit(state.line).status() != LineLib.STATUS.REPAID // if repaid, skip;
        ) {
            revert UnderCollateralized();
        }

        emit RemoveCollateral(token, amount);

        return cratio;
    }

    /**
     * @notice updates the cratio according to the collateral value vs line value
     * @dev calls accrue interest on the line contract to update the latest interest payable
     * @return the updated collateral ratio in 18 decimals
     */
    function _getLatestCollateralRatio() internal returns (uint256) {
        (uint256 principal, uint256 interest) = ILineOfCredit(state.line)
            .updateOutstandingDebt();
        uint256 debtValue = principal + interest;
        uint256 collateralValue = state._getCollateralValue(oracle);
        if (collateralValue == 0) return 0;
        if (debtValue == 0) return EscrowLib.MAX_INT;

        return EscrowLib._percent(collateralValue, debtValue, 18);
    }

    /**
     * @notice calculates the cratio
     * @dev callable by anyone
     * @return - the calculated cratio
     */
    function getCollateralRatio() external returns (uint256) {
        return _getLatestCollateralRatio();
    }

    /**
     * @notice calculates the collateral value in USD to 8 decimals
     * @dev callable by anyone
     * @return - the calculated collateral value to 8 decimals
     */
    function getCollateralValue() external returns (uint256) {
        return state._getCollateralValue(oracle);
    }

    function liquidate(
        uint256 amount,
        address token,
        address to
    ) external returns (bool) {
        return state.liquidate(amount, token, to);
    }
}
