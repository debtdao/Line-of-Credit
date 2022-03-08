
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
