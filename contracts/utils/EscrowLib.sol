pragma solidity 0.8.9;

import { Denominations } from "chainlink/Denominations.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20}  from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
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

    function isLiquidatable(EscrowState storage self, address oracle, uint256 minimumCollateralRatio) external returns(bool) {
      return _getLatestCollateralRatio(self, oracle) < minimumCollateralRatio;
    }

    function updateLine(EscrowState storage self, address _line) external returns(bool) {
      require(msg.sender == self.line);
      self.line = _line;
      return true;
    }

    /**
     * @notice updates the cratio according to the collateral value vs line value
     * @dev calls accrue interest on the line contract to update the latest interest payable
     * @return the updated collateral ratio in 18 decimals
     */
    function _getLatestCollateralRatio(EscrowState storage self, address oracle) public returns (uint256) {
        (uint256 principal, uint256 interest) = ILineOfCredit(self.line).updateOutstandingDebt();
        uint256 debtValue =  principal + interest;
        uint256 collateralValue = _getCollateralValue(self, oracle);
        if (collateralValue == 0) return 0;
        if (debtValue == 0) return MAX_INT;

        uint256 _numerator = collateralValue * 10**5; // scale to 2 decimals
        return ((_numerator / debtValue) + 5) / 10;
    }

    /**
    * @dev calculate the USD value of all the collateral stored
    * @return - the collateral's USD value in 8 decimals
    */
    function _getCollateralValue(EscrowState storage self, address oracle) public returns (uint256) {
        uint256 collateralValue;
        // gas savings
        uint256 length = self.collateralTokens.length;
        IOracle o = IOracle(oracle); 
        IEscrow.Deposit memory d;
        for (uint256 i; i < length; ++i) {
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

    function addCollateral(EscrowState storage self, address oracle, uint256 amount, address token)
        external
        returns (uint256)
    {
        require(amount > 0);
        if(!self.enabled[token])  { revert InvalidCollateral(); }

        LineLib.receiveTokenOrETH(token, msg.sender, amount);

        self.deposited[token].amount += amount;

        emit AddCollateral(token, amount);

        return _getLatestCollateralRatio(self, oracle);
    }

    function enableCollateral(EscrowState storage self, address oracle, address token) external returns (bool) {
        require(msg.sender == ILineOfCredit(self.line).arbiter());

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

        return true;
    }

    function releaseCollateral(
        EscrowState storage self,
        address borrower,
        address oracle,
        uint256 minimumCollateralRatio,
        uint256 amount,
        address token,
        address to
    ) external returns (uint256) {
        require(amount > 0);
        if(msg.sender != borrower) { revert CallerAccessDenied(); }
        if(self.deposited[token].amount < amount) { revert InvalidCollateral(); }
        self.deposited[token].amount -= amount;
        
        LineLib.sendOutTokenOrETH(token, to, amount);

        uint256 cratio = _getLatestCollateralRatio(self, oracle);
        // fail if reduces cratio below min 
        // but allow borrower to always withdraw if fully repaid
        if(
          cratio < minimumCollateralRatio &&         // if undercollateralized, revert;
          ILineOfCredit(self.line).status() != LineLib.STATUS.REPAID // if repaid, skip;
        ) { revert UnderCollateralized(); }
        
        emit RemoveCollateral(token, amount);

        return cratio;
    }

    function getCollateralRatio(EscrowState storage self, address oracle) external returns (uint256) {
        return _getLatestCollateralRatio(self, oracle);
    }

    function getCollateralValue(EscrowState storage self, address oracle) external returns (uint256) {
        return _getCollateralValue(self, oracle);
    }

    function liquidate(
        EscrowState storage self,
        uint256 amount,
        address token,
        address to
    ) external returns (bool) {
        require(amount > 0);
        if(msg.sender != self.line) { revert CallerAccessDenied(); }
        if(self.deposited[token].amount < amount) { revert InvalidCollateral(); }

        self.deposited[token].amount -= amount;
        
        LineLib.sendOutTokenOrETH(token, to, amount);

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
