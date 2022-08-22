pragma solidity 0.8.9;

import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEscrow} from "../../interfaces/IEscrow.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";
import {CreditLib} from "../../utils/CreditLib.sol";
import {LineLib} from "../../utils/LineLib.sol";

library EscrowLib {
    using SafeERC20 for IERC20;

    // return if have collateral but no debt
    uint256 constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function isLiquidatable(IEscrow.State storage state)
        external
        returns (bool)
    {
        return _getLatestCollateralRatio(state) < state.minimumCollateralRatio;
    }

    function updateLine(IEscrow.State storage state, address _line)
        external
        returns (bool)
    {
        require(msg.sender == state.line);
        state.line = _line;
        return true;
    }

    /**
     * @notice updates the cratio according to the collateral value vs line value
     * @dev calls accrue interest on the line contract to update the latest interest payable
     * @return the updated collateral ratio in 18 decimals
     */
    function _getLatestCollateralRatio(IEscrow.State storage state)
        internal
        returns (uint256)
    {
        (uint256 principal, uint256 interest) = ILineOfCredit(state.line)
            .updateOutstandingDebt();
        uint256 debtValue = principal + interest;
        uint256 collateralValue = _getCollateralValue(state);
        if (collateralValue == 0) return 0;
        if (debtValue == 0) return MAX_INT;

        return _percent(collateralValue, debtValue, 18);
    }

    /**
     * @notice - computes the ratio of one value to another
               - e.g. _percent(100, 100, 18) = 1 ether = 100%
     * @param numerator - value to compare
     * @param denominator - value to compare against
     * @param precision - number of decimal places of accuracy to return in answer 
     * @return quotient -  the result of num / denom
    */
    function _percent(
        uint256 numerator,
        uint256 denominator,
        uint256 precision
    ) internal pure returns (uint256 quotient) {
        uint256 _numerator = numerator * 10**(precision + 1);
        // with rounding of last digit
        uint256 _quotient = ((_numerator / denominator) + 5) / 10;
        return (_quotient);
    }

    /**

    * @dev calculate the USD value of all the collateral stored
    * @return - the collateral's USD value in 8 decimals
    */
    function _getCollateralValue(IEscrow.State storage state)
        internal
        returns (uint256)
    {
        uint256 collateralValue = 0;
        // gas savings
        uint256 length = state.collateralTokens.length;
        IOracle o = IOracle(state.oracle);
        IEscrow.Deposit memory d;
        for (uint256 i = 0; i < length; i++) {
            address token = state.collateralTokens[i];
            d = state.deposited[token];
            // new var so we don't override original deposit amount for 4626 tokens
            uint256 deposit = d.amount;
            if (deposit != 0) {
                if (d.isERC4626) {
                    // this conversion could shift, hence it is best to get it each time
                    (bool success, bytes memory assetAmount) = token.call(
                        abi.encodeWithSignature(
                            "previewRedeem(uint256)",
                            deposit
                        )
                    );
                    if (!success) continue;
                    deposit = abi.decode(assetAmount, (uint256));
                }

                collateralValue += CreditLib.calculateValue(
                    o.getLatestAnswer(d.asset),
                    deposit,
                    d.assetDecimals
                );
            }
        }

        return collateralValue;
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
    function addCollateral(
        IEscrow.State storage state,
        uint256 amount,
        address token
    ) external returns (uint256) {
        require(amount > 0);
        if (!state.enabled[token]) {
            revert IEscrow.InvalidCollateral();
        }

        LineLib.receiveTokenOrETH(token, msg.sender, amount);

        state.deposited[token].amount += amount;

        emit AddCollateral(token, amount);

        return _getLatestCollateralRatio(state);
    }

    /**
     * @notice - allows  the lines arbiter to  enable thdeposits of an asset
     *        - gives  better risk segmentation forlenders
     * @dev - whitelisting protects against malicious 4626 tokens and DoS attacks
     *       - only need to allow once. Can not disable collateral once enabled.
     * @param token - the token to all borrow to deposit as collateral
     */
    function enableCollateral(IEscrow.State storage state, address token)
        external
        returns (bool)
    {
        require(msg.sender == ILineOfCredit(state.line).arbiter());

        _enableToken(state, token);

        return true;
    }

    /**
    * @notice track the tokens used as collateral. Ensures uniqueness,
              flags if its a EIP 4626 token, and gets its decimals
    * @dev - if 4626 token then Deposit.asset s the underlying asset, not the 4626 token
    * return bool - if collateral is now enabled or not.
    */
    function _enableToken(IEscrow.State storage state, address token)
        internal
        returns (bool)
    {
        bool isEnabled = state.enabled[token];
        IEscrow.Deposit memory deposit = state.deposited[token]; // gas savings
        if (!isEnabled) {
            if (token == Denominations.ETH) {
                // enable native eth support
                deposit.asset = Denominations.ETH;
                deposit.assetDecimals = 18;
            } else {
                (bool passed, bytes memory tokenAddrBytes) = token.call(
                    abi.encodeWithSignature("asset()")
                );

                bool is4626 = tokenAddrBytes.length > 0 && passed;
                deposit.isERC4626 = is4626;
                // if 4626 save the underlying token to use for oracle pricing
                deposit.asset = !is4626
                    ? token
                    : abi.decode(tokenAddrBytes, (address));

                int256 price = IOracle(state.oracle).getLatestAnswer(
                    deposit.asset
                );
                if (price <= 0) {
                    revert IEscrow.InvalidCollateral();
                }

                (bool successDecimals, bytes memory decimalBytes) = deposit
                    .asset
                    .call(abi.encodeWithSignature("decimals()"));
                if (decimalBytes.length > 0 && successDecimals) {
                    deposit.assetDecimals = abi.decode(decimalBytes, (uint8));
                } else {
                    deposit.assetDecimals = 18;
                }
            }

            // update collateral settings
            state.enabled[token] = true;
            state.deposited[token] = deposit;
            state.collateralTokens.push(token);
            emit EnableCollateral(deposit.asset);
        }

        return isEnabled;
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
        IEscrow.State storage state,
        uint256 amount,
        address token,
        address to
    ) external returns (uint256) {
        require(amount > 0);
        if (msg.sender != state.borrower) {
            revert IEscrow.CallerAccessDenied();
        }
        if (state.deposited[token].amount < amount) {
            revert IEscrow.InvalidCollateral();
        }
        state.deposited[token].amount -= amount;

        LineLib.sendOutTokenOrETH(token, to, amount);

        uint256 cratio = _getLatestCollateralRatio(state);
        // fail if reduces cratio below min
        // but allow borrower to always withdraw if fully repaid
        if (
            cratio < state.minimumCollateralRatio && // if undercollateralized, revert;
            ILineOfCredit(state.line).status() != LineLib.STATUS.REPAID // if repaid, skip;
        ) {
            revert IEscrow.UnderCollateralized();
        }

        emit RemoveCollateral(token, amount);

        return cratio;
    }

    /**
     * @notice calculates the cratio
     * @dev callable by anyone
     * @return - the calculated cratio
     */
    function getCollateralRatio(IEscrow.State storage state)
        external
        returns (uint256)
    {
        return _getLatestCollateralRatio(state);
    }

    /**
     * @notice calculates the collateral value in USD to 8 decimals
     * @dev callable by anyone
     * @return - the calculated collateral value to 8 decimals
     */
    function getCollateralValue(IEscrow.State storage state)
        external
        returns (uint256)
    {
        return _getCollateralValue(state);
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
        IEscrow.State storage state,
        uint256 amount,
        address token,
        address to
    ) external returns (bool) {
        require(amount > 0);
        if (msg.sender != state.line) {
            revert IEscrow.CallerAccessDenied();
        }
        if (state.deposited[token].amount < amount) {
            revert IEscrow.InvalidCollateral();
        }

        state.deposited[token].amount -= amount;

        LineLib.sendOutTokenOrETH(token, to, amount);

        emit Liquidate(token, amount);

        return true;
    }

    event AddCollateral(address indexed token, uint256 indexed amount);

    event EnableCollateral(address indexed token);

    event RemoveCollateral(address indexed token, uint256 indexed amount);

    event Liquidate(address indexed token, uint256 indexed amount);
}
