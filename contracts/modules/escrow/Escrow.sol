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
    uint32 public immutable minimumCollateralRatio;

    // Stakeholders and contracts used in Escrow
    address public immutable oracle;
    address public immutable borrower;

    EscrowState private state;

    constructor(
        uint32 _minimumCollateralRatio,
        address _oracle,
        address _line,
        address _borrower
    ) {
        minimumCollateralRatio = _minimumCollateralRatio;
        oracle = _oracle;
        state.line = _line;
        borrower = _borrower;
    }

    function line() external view override returns(address) {
      return state.line;
    }

    function isLiquidatable() external returns(bool) {
      return state.isLiquidatable(oracle, minimumCollateralRatio);
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
        external payable
        returns (uint256)
    {
        return state.addCollateral(oracle, amount, token);
    }

    /**
     * @notice - allows  the lines arbiter to  enable thdeposits of an asset
     *        - gives  better risk segmentation forlenders
     * @dev - whitelisting protects against malicious 4626 tokens and DoS attacks
     *       - only need to allow once. Can not disable collateral once enabled.
     * @param token - the token to all borrow to deposit as collateral
     */
    function enableCollateral(address token) external returns (bool) {
        return state.enableCollateral(oracle, token);
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
        return state.releaseCollateral(borrower, oracle, minimumCollateralRatio, amount, token, to);
    }

    /**
     * @notice calculates the cratio
     * @dev callable by anyone
     * @return - the calculated cratio
     */
    function getCollateralRatio() external returns (uint256) {
        return state.getCollateralRatio(oracle);
    }

    /**
     * @notice calculates the collateral value in USD to 8 decimals
     * @dev callable by anyone
     * @return - the calculated collateral value to 8 decimals
     */
    function getCollateralValue() external returns (uint256) {
        return state.getCollateralValue(oracle);
    }

    /**
     * @notice liquidates borrowers collateral by token and amount
     *         line can liquidate at anytime based off other covenants besides cratio
     * @dev requires that the cratio is at or below the liquidation threshold
     * @dev callable by `line`
     * @param amount - the amount of tokens to liquidate
     * @param token - the address of the token to draw funds from
     * @param to - the address to receive the funds
     * @return - true if successful
     */
    function liquidate(
        uint256 amount,
        address token,
        address to
    ) external returns (bool) {
        return state.liquidate(amount, token, to);
    }
}
