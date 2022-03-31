pragma solidity 0.8.9;

import { IEscrow } from "./interfaces/IEscrow.sol";
import { LoanLib } from "./lib/LoanLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOracle } from "./interfaces/IOracle.sol";
import { ILoan } from "./interfaces/ILoan.sol";

contract Escrow is IEscrow {

    // the minimum value of the collateral in relation to the outstanding debt e.g. 10% of outstanding debt
    uint public minimumCollateralRatio;

    // Stakeholders and contracts used in Escrow
    address public loan;
    address public oracle;
    address public lender;
    address public borrower;
    address public arbiter;

    // this status can constantly change, hence last updated status
    LoanLib.STATUS public lastUpdatedStatus;

    // tracking tokens that were deposited
    address[] private _tokensUsedAsCollateral;

    // mapping to check uniqueness of tokensUsedAsCollateral
    mapping(address => bool) private _tokensUsed;

    // tokens used as collateral (must be able to value with oracle)
    mapping(address => uint) public deposited;

    // collateral tokens that have been used for farming
    mapping(address => Farm) public farmedTokens;

    constructor(
        uint _minimumCollateralRatio,
        address _oracle,
        address _lender,
        address _borrower,
        address _arbiter
    ) public {
        minimumCollateralRatio = minimumCollateralRatio;
        oracle = _oracle;
        lender = _lender;
        borrower = _borrower;
        arbiter = _arbiter;
        lastUpdatedStatus = LoanLib.STATUS.UNINITIALIZED;
    }

    /*
    * @dev see IModule.sol
    */
    function init() external returns(bool) {
        require(lastUpdatedStatus == LoanLib.STATUS.UNINITIALIZED, "Escrow: init() has already been called");
        lastUpdatedStatus = LoanLib.STATUS.INITIALIZED;
        loan = msg.sender;

        return true;
    }

    /*
    * @dev see IEscrow.sol
    */
    function activate(address[] calldata tokensToDeposit, uint[] calldata amounts) external returns(bool) {
        require(msg.sender == borrower, "Escrow: only borrower can call");
        require(lastUpdatedStatus == LoanLib.STATUS.INITIALIZED, "Escrow: must be in the initialized status");
        require(tokensToDeposit.length == amounts.length, "Escrow: array length mismatch");
        for(uint i = 0; i < tokensToDeposit.length; i++) {
            require(IOracle(oracle).getLatestAnswer(tokensToDeposit[i]) != 0, "Escrow: token cannot be valued");
            require(IERC20(tokensToDeposit[i]).transferFrom(borrower, address(this), amounts[i]));
            deposited[tokensToDeposit[i]] += amounts[i];
            _addTokenUsed(tokensToDeposit[i]);
            emit CollateralAdded(tokensToDeposit[i], amounts[i]);
        }
        lastUpdatedStatus = LoanLib.STATUS.ACTIVE;

        return true;
    }

    /*
    * @dev see IModule.sol
    */
    function healthcheck() public returns (LoanLib.STATUS status) {
        if(lastUpdatedStatus == LoanLib.STATUS.UNINITIALIZED
            || lastUpdatedStatus == LoanLib.STATUS.INITIALIZED
        ) {
            return lastUpdatedStatus;
        }
        uint cratio = _getLatestCollateralRatio();
        if(cratio > minimumCollateralRatio) {
            lastUpdatedStatus = LoanLib.STATUS.ACTIVE;
        } else {
            lastUpdatedStatus = LoanLib.STATUS.LIQUIDATABLE;
        }

        return lastUpdatedStatus;
    }

    /*
    * @dev updates the cratio according to the collateral value vs loan value
    * @returns the updated collateral ratio
    */
    function _getLatestCollateralRatio() internal returns(uint) {
        // TODO sanity check the math here
        uint debtValue = ILoan(loan).accrueInterest();
        uint collateralValue = _getCollateralValue();

        return collateralValue / debtValue;
    }

    /*
    * @dev calculate the USD value of the collateral stored
    * @returns - the collateral's USD value
    */
    function _getCollateralValue() internal returns(uint) {
        uint collateralValue = 0;
        for(uint i = 0; i < _tokensUsedAsCollateral.length; i++) {
            uint price = IOracle(oracle).getLatestAnswer(_tokensUsedAsCollateral[i]);
            // TODO will need to scale by token decimal
            // uint tokenDecimals = IERC20(_tokensUsedAsCollateral[i]).decimals();
            // collateralValue += price * (deposited[_tokensUsedAsCollateral[i]] / tokenDecimals);
            collateralValue += price * deposited[_tokensUsedAsCollateral[i]];
        }

        return collateralValue;
    }

    /*
    * @dev see IEscrow.sol
    */
    function addCollateral(uint amount, address token) external returns(uint) {
        require(
            lastUpdatedStatus == LoanLib.STATUS.ACTIVE
            || lastUpdatedStatus == LoanLib.STATUS.LIQUIDATABLE,
            "Escrow: must be in the ACTIVE/LIQUIDATABLE status"
        );
        require(
            IOracle(oracle).getLatestAnswer(token) != 0,
            "Escrow: deposited token does not have a price feed"
        );
        require(IERC20(token).transferFrom(msg.sender, address(this), amount));
        deposited[token] += amount;
        emit CollateralAdded(token, amount);
        _addTokenUsed(token);

        return _getLatestCollateralRatio();
    }

    function _addTokenUsed(address token) internal {
        if(!_tokensUsed[token]) {
            _tokensUsed[token] = true;
            _tokensUsedAsCollateral.push(token);
        }
    }

    /*
    * @dev see IEscrow.sol
    */
    function releaseCollateral(uint amount, address token, address to) external returns(uint) {
        require(msg.sender == borrower, "Escrow: only borrower can call");
        require(IERC20(token).transferFrom(address(this), to, amount));
        deposited[token] -= amount;
        uint cratio = _getLatestCollateralRatio();
        require(cratio >= minimumCollateralRatio, "Escrow: cannot release collateral if cratio becomes lower than the minimum");
        emit CollateralRemoved(token, amount);

        return cratio;
    }

    /*
    * @dev see IEscrow.sol
    */
    function getCollateralRatio() external returns(uint) {
        return _getLatestCollateralRatio();
    }

    /*
    * @dev see IEscrow.sol
    */
    function liquidate(address token, uint amount) external {
        require(msg.sender == loan, "Escrow: msg.sender must be the loan contract");
        require(healthcheck() == LoanLib.STATUS.LIQUIDATABLE, "Escrow: not eligible for liquidation");
        require(IERC20(token).transferFrom(address(this), arbiter, amount));
        deposited[token] -= amount;
        emit Liquidated(token, amount);
    }

    // TODO @smokey
    function stakeCollateral(address token, uint amount, Farm memory farm) external {
        revert("Not implemented");
    }

    function unstakeCollateral(address token, uint amount, Farm memory farm) external {
        revert("Not implemented");
    }

    function claimStakingRewards(address[] memory farmedTokens) external {
        revert("Not implemented");
    }
}