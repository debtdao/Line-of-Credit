
/**
 * @title Spigot Consumer Module for Debt DAO P2P Loans
 * @author Kiba Gateaux
 * @notice Used to programmatically manage a spigot for a loan contract
 * @dev Should be deployed once per Loan/Spigot
 */
contract SpigotConsumer {
  Spigot immutable public spigot;

  address immutable public swapTarget;

  uint8 immutable public defaultRevenueSplit;

  uint8 constant MAX_SPLIT =  100;


  constructor(
    address swapTarget_,
    address borrower,
    uint8 defaultSplit
  ) {
    spigot = new Spigot(address(this), borrower, borrower, [], [], []);
    
    defaultRevenueSplit = defaultSplit;

    swapTarget = swapTarget_;
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
