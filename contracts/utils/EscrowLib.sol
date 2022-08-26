pragma solidity 0.8.9;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {CreditLib} from "../utils/CreditLib.sol";
import {LineLib} from "../utils/LineLib.sol";

struct EscrowState {
    address line;
    address[] collateralTokens;
    /// if lenders allow token as collateral. ensures uniqueness in collateralTokens
    mapping(address => bool) enabled;
    /// tokens used as collateral (must be able to value with oracle)
    mapping(address => IEscrow.Deposit) deposited;
}

library EscrowLib {
    using SafeERC20 for IERC20;

    // return if have collateral but no debt
    uint256 constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function getLine(EscrowState storage self) external view returns (address) {
        return self.line;
    }

    function getDeposited(EscrowState storage self, address token)
        external
        view
        returns (IEscrow.Deposit memory)
    {
        return self.deposited[token];
    }

    function updateLine(EscrowState storage self, address _line)
        external
        returns (bool)
    {
        require(msg.sender == self.line);
        self.line = _line;
        return true;
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
    ) external pure returns (uint256 quotient) {
        uint256 _numerator = numerator * 10**(precision + 1);
        // with rounding of last digit
        uint256 _quotient = ((_numerator / denominator) + 5) / 10;
        return (_quotient);
    }

    /**

    * @dev calculate the USD value of all the collateral stored
    * @return - the collateral's USD value in 8 decimals
    */
    function _getCollateralValue(EscrowState storage self, address oracle)
        external
        returns (uint256)
    {
        uint256 collateralValue = 0;
        // gas savings
        uint256 length = self.collateralTokens.length;
        IOracle o = IOracle(oracle);
        IEscrow.Deposit memory d;
        for (uint256 i = 0; i < length; i++) {
            address token = self.collateralTokens[i];
            d = self.deposited[token];
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
     * @notice - allows  the lines arbiter to  enable thdeposits of an asset
     *        - gives  better risk segmentation forlenders
     * @dev - whitelisting protects against malicious 4626 tokens and DoS attacks
     *       - only need to allow once. Can not disable collateral once enabled.
     * @param token - the token to all borrow to deposit as collateral
     */
    function enableCollateral(
        EscrowState storage self,
        address token,
        address oracle
    ) external returns (bool) {
        require(msg.sender == ILineOfCredit(self.line).arbiter());

        EscrowLib._enableToken(self, token, oracle);

        return true;
    }

    /**
    * @notice track the tokens used as collateral. Ensures uniqueness,
              flags if its a EIP 4626 token, and gets its decimals
    * @dev - if 4626 token then Deposit.asset s the underlying asset, not the 4626 token
    * return bool - if collateral is now enabled or not.
    */
    function _enableToken(
        EscrowState storage self,
        address token,
        address oracle
    ) internal returns (bool) {
        bool isEnabled = self.enabled[token];
        IEscrow.Deposit memory deposit = self.deposited[token]; // gas savings
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

                int256 price = IOracle(oracle).getLatestAnswer(deposit.asset);
                if (price <= 0) {
                    revert InvalidCollateral();
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
            self.enabled[token] = true;
            self.deposited[token] = deposit;
            self.collateralTokens.push(token);
            emit EnableCollateral(deposit.asset);
        }

        return isEnabled;
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
        EscrowState storage self,
        uint256 amount,
        address token,
        address to
    ) external returns (bool) {
        require(amount > 0);
        if (msg.sender != self.line) {
            revert CallerAccessDenied();
        }
        if (self.deposited[token].amount < amount) {
            revert InvalidCollateral();
        }

        self.deposited[token].amount -= amount;

        LineLib.sendOutTokenOrETH(token, to, amount);

        emit Liquidate(token, amount);

        return true;
    }

    event AddCollateral(address indexed token, uint256 indexed amount);

    event RemoveCollateral(address indexed token, uint256 indexed amount);

    event EnableCollateral(address indexed token);

    event Liquidate(address indexed token, uint256 indexed amount);

    error InvalidCollateral();

    error CallerAccessDenied();

    error UnderCollateralized();

    error NotLiquidatable();
}
