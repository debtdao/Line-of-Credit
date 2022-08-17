pragma solidity ^0.8.9;

import {ISpigot} from "./ISpigot.sol";

interface ISpigotedLoan {
  event RevenuePayment(
    address indexed token,
    uint256 indexed amount
    // dont need to track value like other events because _repay already emits
    // this event is just semantics/helper to track payments from revenue specifically
  );




  // Borrower functions
  function useAndRepay(uint256 amount) external returns(bool);
  function claimAndRepay(address token, bytes calldata zeroExTradeData) external returns(uint256);
  function claimAndTrade(address token,  bytes calldata zeroExTradeData) external returns(uint256 tokensBought);
  
  // Manage Spigot functions
  function addSpigot(address revenueContract, ISpigot.Setting calldata setting) external returns(bool);
  function updateWhitelist(bytes4 func, bool allowed) external returns(bool);
  function updateOwnerSplit(address revenueContract) external returns(bool);
  function releaseSpigot() external returns(bool);


  function sweep(address to, address token) external returns(uint256);

  // getters
  function unused(address token) external returns(uint256);
}
