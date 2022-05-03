
/**
 * @title Spigot Consumer Module for Debt DAO P2P Loans
 * @author Kiba Gateaux
 * @notice Used to programmatically manage a spigot for a loan contract
 * @dev Should be deployed once per Loan/Spigot
 */
contract SpigotConsumer {
  constructor() {

  }

  function claimAndTrade(
    address claimToken, 
    address targetToken, 
    bytes[] calldata zeroExTradeData
  )
    external
    returns(uint256 tokensBought)
  {
    // require caller == loan
    // checkpoint this balance before trade
    // call zeroex exchange 
    // check token balance afterwards
    // add
  }
  function stream(address lender, address token, uint256 amount) external returns(bool) {
    //
  }
}
