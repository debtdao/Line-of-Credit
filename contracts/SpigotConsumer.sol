import { ISpigot } from "./interfaces/ISpigot.sol";
import { ISpigotConsumer } from "./interfaces/ISpigotConsumer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Spigot Consumer Module for Debt DAO P2P Loans
 * @author Kiba Gateaux
 * @notice Used to progromattically manage a spigot for a loan contract
 * @dev Should be deployed once per Loan/Spigot
 */
contract SpigotConsumer is ISpigotConsumer, ReentrancyGuard {
  address immutable ZERO_EX_EXCHANGE;
  
  ISpigot immutable spigot;
  address immutable loan;
  constructor(
    address _spigot,
    address _loan,
    address exchangeAddress
  ) {
    spigot = ISpigot(_spigot);
    loan = _loan;
    ZERO_EX_EXCHANGE = exchangeAddress;
  }

  modifier onlyLoan() {
    require(msg.sender == loan);
    _;
  }

  /**
   * @notice Transfers ownership of spigot and all revenue streams it holds to new address.
   *          Used to give borrower control after loan repaid or repo if defaulted. 
   * @dev This will prevent SpigotConsumer from working and may cause calls to Loan to fail.
   * @param newOwner - address thst will control spigot 
   * @return success bool
   */
  function transferSpigotOwner(address newOwner) external onlyLoan returns(bool) {
    require(spigot.updateOwner(newOwner));
    return true;
  }

  /**
   * @notice Update % revenue split between Spigot and borrower
   * @dev assumes validity checks to be done in Spigot contract
   * @param revenueContract- spigot to uopate split on
   * @param newSplit - % revenue split going forward
   * @return success bool
   */
  function updateRevenueSplit(address revenueContract, uint8 newSplit) external onlyLoan returns(bool) {
    require(spigot.updateOwnerSplit(revenueContract, newSplit));
    return true;
  }

  /**
   * @notice Claims revenues tokens from Spigot and trades them on 0x to a token that borrwer lent out
   * @param claimToken- revenue token escrowed in Spigot to claim
   * @param targetToken- token t hat debt is denominated in that must be repaid
   * @param zeroExTradeData - data returned by 0x API to execute trade
   * @return available amount of `targetToken` that can be used to repay loan
   */
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


  /**
   * @notice 
   * @param token -revenue token escrowed in Spigot to claim
   * @return amount of tokens claimed from Spigot
   */
  function claimTokens(address token) external returns(uint256) {
    return spigot.claimEscrow(token);
  }

  /**
   * @notice Gets the total amount of tokens held in SpigotConsumer + Spigot escrow that can be used to trade for debt tokens
   * @param token - token to retrieve data on
   * @return amount of tokens
   */
  function getTotalTradableTokens(address token) external returns(uint256) {
    return _balanceOf(token) + spigot.getEscrowBalance(token);
  }

  /**
   * @notice Transfers token from SpigotConsumer to `to` address.
             Useful if extra debt tokens held in Soigot Consumer because there is not enough debt to spend them all at the time of claiming/trading
   * @param to - who to send tokens to
   * @param token - token to send
   * @param amount - amoutn of token to send
   * @return success bool
   */
  function stream(address to, address token, uint256 amount)
    external
    nonReentrant
    onlyLoan
    returns(bool)
  {
    require(amount <= _balanceOf(token));

    bool success;
    if(token == address(0)) {
      (success, ) = to.call{value: amount}("");
    } else {
      success = IERC20(token).transfer(to, amount);
    }
    require(success);

    return true;
  }

  function _balanceOf(address token) internal view returns(uint256) {
    return  token == address(0) ?
      address(this).balance :
      IERC20(token).balanceOf(address(this));
  }
}
