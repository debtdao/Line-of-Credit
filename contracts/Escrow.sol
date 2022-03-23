pragma solidity 0.8.9;

import { IEscrow } from "./interfaces/IEscrow.sol";
import { LoanLib } from "./lib/LoanLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Escrow is IEscrow {

    uint public minimumCollateralRatio; // the minimum value of the collateral in relation to the outstanding debt e.g. 10% of outstanding debt
    address public loanContract;
    address public oracle; // used to value assets, must be an approved source
    address public lender;
    address public borrower;
    bool public initCalled = false;
    LoanLib.STATUS currentStatus;
    mapping(address => uint) public deposited; // tokens used as collateral (must be able to value with oracle)
    mapping(address => Farm) public farmedTokens; // collateral tokens that have been used for farming

    constructor(
        uint _minimumCollateralRatio,
        address _loanContract,
        address _oracle
    ) public {
        minimumCollateralRatio = minimumCollateralRatio;
        loanContract = loanContract;
        oracle = _oracle;
        currentStatus = LoanLib.STATUS.UNINITIALIZED; // TODO at what point does the escrow become initialized?
    }

    function init() external {
        // TODO
        require(!initCalled, "Escrow: init() has already been called");
        currentStatus = LoanLib.STATUS.INITIALIZED;
        initCalled = true;
    }

    /*
    * @dev see IModule.sol
    */
    function healthcheck() external returns (LoanLib.STATUS status) {
        revert("Not implemented");
    }

    /*
    * @dev updates the current health status by checking cratio
    */
    function _updateHealthCheck() internal {
        revert("Not implemented");
    }

    /*
    * @dev see IModule.sol
    */
    function loan() external returns (address) {
        return loanContract;
    }

    /*
    * @dev see IEscrow.sol
    */
    function addCollateral(uint amount, address token) public {
        revert("Not implemented");
    }

    /*
    * @dev see IEscrow.sol
    */
    function getCollateralRatio() public returns(uint) {
        revert("Not implemented");
    }

    /*
    * @dev see IEscrow.sol
    */
    function releaseCollateral(uint amount, address token, address to) public {
        revert("Not implemented");
    }

    /*
    * @dev see IEscrow.sol
    */
    function liquidate(address token, uint amount) public {
        revert("Not implemented");
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