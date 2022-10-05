pragma solidity ^0.8.9;

import {ISpigot} from "./ISpigot.sol";

interface ISpigotedLine {
  event RevenuePayment(
    address indexed token,
    uint256 indexed amount
    // Emits the amount of revenue tokens that have been repaid after claimAndRepay
    // dont need to track value like other events because _repay already emits that
    // Mainly used to log debt that is paid via Spigot directly vs other sources. Without this event it's a lot harder to parse that offchain.
    // Bob - similar to the event ClaimEscrow then which also claims revenue tokens
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
