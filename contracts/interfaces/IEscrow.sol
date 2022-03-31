pragma solidity 0.8.9;

import { LoanLib } from "../lib/LoanLib.sol";
import { IModule } from "./IModule.sol";

interface IEscrow is IModule {
    // TODO @smokey
    struct Farm {
        bytes4 depositFunc;
        bytes4 withdrawFunc;
        address[] rewardTokens;
    }

    event CollateralAdded(address indexed token, uint amount);
    event CollateralRemoved(address indexed token, uint amount);
    event CollateralFarmed(address indexed token, uint amount);
    event CollateralRemovedFromFarm(address indexed token, uint amount);
    event Liquidated(address indexed token, uint amount);

    /*
    * @dev only borrower can call
    * @dev sets the status to "active" and allows the borrower to post collateral and be eligible for the loan
    * @dev requires that the tokens deposited can be valued by the escrow's oracle
    * @param tokensToDeposit - the token addresses of the deposited tokens
    * @param amounts - the amounts of collateral to add
    * @returns - boolean
    */
    function activate(address[] calldata tokensToDeposit, uint[] calldata amounts) external returns(bool);

    /*
    * @dev add collateral to your position
    * @dev anyone can call
    * @dev updates cratio
    * @dev requires that the token deposited can be valued by the escrow's oracle & the depositor has approved this contract
    * @param amount - the amount of collateral to add
    * @param token - the token address of the deposited token
    * @returns - the updated cratio
    */
    function addCollateral(uint amount, address token) external returns(uint);

    /*
    * @dev calculates the cratio
    * @dev anyone can call
    * @returns - the calculated cratio
    */
    function getCollateralRatio() external returns(uint);

    /*
    * @dev remove collateral from your position
    * @dev requires that cratio is still acceptable & msg.sender == borrower
    * @dev updates cratio
    * @param amount - the amount of collateral to release
    * @param token - the token address to withdraw
    * @param to - who should receive the funds
    * @returns - the updated cratio
    */
    function releaseCollateral(uint amount, address token, address to) external returns(uint);

    /*
    * @dev liquidates borrowers collateral by token and amount
    * @dev requires that the cratio is at the liquidation threshold & msg.sender == loanAddress
    * @dev sends funds to the arbiter address (obtained from the loan contract)
    * @param token - the address of the token to draw funds from
    * @param amount - the amount of tokens to liquidate
    */
    function liquidate(address token, uint amount) external;

    // TODO @smokey
    function stakeCollateral(address token, uint amount, Farm memory farm) external;
    function unstakeCollateral(address token, uint amount, Farm memory farm) external;
    function claimStakingRewards(address[] memory farmedTokens) external;

    function healthcheck() external returns (LoanLib.STATUS status);
}
