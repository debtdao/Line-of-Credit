pragma solidity 0.8.9;

import { LoanLib } from "../lib/LoanLib.sol";

interface IModule {
    function healthcheck() external returns (LoanLib.STATUS status);
    function loan() external returns (address);
}
