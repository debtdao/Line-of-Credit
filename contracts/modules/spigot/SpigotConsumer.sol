import { SpigotController } from "./Spigot.sol";

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

  function _claimAndTrade(
    address claimToken, 
    address targetToken, 
    bytes[] calldata zeroExTradeData
  )
    internal
    returns(uint256 targetTokensOwned)
  {
    uint256 tokensClaimed = spigot.claimEscrow(claimToken);
    uint256 existingTargetTokensOwned = IERC20(targetToken).balanceOf(address(this));

    if(claimToken == address(0)) {
      // if claiming/trading eth send as msg.value to dex
      (bool success, bytes[] data) = swapTarget.call{value: tokensClaimed}(zeroExTradeData);
      require(success, 'SpigotCnsm: trade failed');
    } else {
      IERC20(claimToken).approve(swapTarget, tokensClaimed);
      (bool success, ) = swapTarget.call(zeroExTradeData);
      require(success, 'SpigotCnsm: trade failed');
    }

    uint256 targetTokensOwned = IERC20(targetToken).balanceOf(address(this));

    // ideally we could use oracle to calculate # of tokens to receive
    // claimToken might not have oracle but targetToken must have token
    require(targetTokensOwned > existingTargetTokensOwned, 'SpigotCnsm: bad trade');

    emit TradeSpigotRevenue(
      claimToken,
      tokensClaimed,
      targetToken,
      targetTokensOwned - existingTargetTokensOwned
    );

    return targetTokensOwned;
  }

  function sweep(address token) external returns(uint256) {
    if(loanStatus == LoanLib.STATUS.REPAID) {
      bool success = IERC20(token).transfer(borrower, IERC20(token).balanceOf(address(this)));
      require(success);
    }
    if(loanStatus == LoanLib.STATUS.INSOLVENT) {
      bool success = IERC20(token).transfer(borrower, IERC20(token).balanceOf(address(this)));
      require(success);
    }
  }
}
