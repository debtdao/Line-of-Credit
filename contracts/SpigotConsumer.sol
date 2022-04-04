import { ISpigot } from "./interfaces/ISpigot.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Spigot Consumer Module for Debt DAO P2P Loans
 * @author Kiba Gateaux
 * @notice Used to progromattically manage a spigot for a loan contract
 * @dev Should be deployed once per Loan/Spigot
 */
contract SpigotConsumer is ReentrancyGuard {
  address constant ZERO_EX_EXCHANGE = address(0);
  
  ISpigot immutable spigot;
  address immutable loan;
  constructor(
    address _spigot,
    address _loan
  ) {
    spigot = ISpigot(_spigot);
    loan = _loan;
  }

  modifier onlyLoan() {
    require(msg.sender == loan);
    _;
  }

  function transferSpigotOwner(address newOwner) external onlyLoan returns(bool) {
    require(spigot.updateOwner(newOwner));
    return true;
  }

  function updateRevenueSplit(address revenueContract, uint8 newSplit) external onlyLoan returns(bool) {
    require(spigot.updateOwnerSplit(revenueContract, newSplit));
    return true;
  }

  function claimAndTrade(
    address claimToken, 
    address targetToken, 
    bytes calldata zeroExTradeData
  )
    external
    nonReentrant
    onlyLoan
    returns(uint256)
  {
    uint256 existingDebtTokenBalance = _balanceOf(targetToken);
    
    uint256 claimedAmount = spigot.claimEscrow(claimToken);

    bool success;
    if(claimToken == address(0) ) {
      // if claiming ETH from Spigot, pass it in as msg.value
      (success, ) = ZERO_EX_EXCHANGE.call{value: claimedAmount}(zeroExTradeData);
    } else {
      IERC20(claimToken).approve(ZERO_EX_EXCHANGE, claimedAmount);
      (success, ) = ZERO_EX_EXCHANGE.call(zeroExTradeData);
    }
    require(success, 'SpgCnsm: trade failed');
    
    uint256 newBalance = _balanceOf(targetToken);
    require(newBalance > existingDebtTokenBalance, 'SpgCnsm: bad trade');
    
    return newBalance;
  }

  function claimTokens(address token) external returns(uint256) {
    return spigot.claimEscrow(token);
  }

  function getTotalTradableTokens(address token) external returns(uint256) {
    return _balanceOf(token) + spigot.getEscrowBalance(token);
  }

  /**
   * @notice sends tokens claimed/traded from spigot revenue to
   */
  function stream(address lender, address token, uint256 amount)
    external
    nonReentrant
    onlyLoan
    returns(bool)
  {
    require(amount <= _balanceOf(token));

    bool success;
    if(token == address(0)) {
      (success, ) = lender.call{value: amount}("");
    } else {
      success = IERC20(token).transfer(lender, amount);
    }
    require(success);
  }

  function _balanceOf(address token) internal view returns(uint256) {
    return  token == address(0) ?
      address(this).balance :
      IERC20(token).balanceOf(address(this));
  }
}
