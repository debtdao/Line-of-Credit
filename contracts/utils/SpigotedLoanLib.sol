pragma solidity 0.8.9;

import { ISpigot } from "../interfaces/ISpigot.sol";
import { ISpigotedLoan } from "../interfaces/ISpigotedLoan.sol";
import { LoanLib } from "../utils/LoanLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";

library SpigotedLoanLib {
    error BadTradingPair();

    error TradeFailed();

    error UsedExcessTokens(address token, uint256 amountAvailable);

    event TradeSpigotRevenue(
        address indexed revenueToken,
        uint256 revenueTokenAmount,
        address indexed debtToken,
        uint256 indexed debtTokensBought
    );


    /**
     * @notice allows tokens in escrow to be sold immediately but used to pay down credit later
     * @dev MUST trade all available claim tokens to target
     * @dev    priviliged internal function
     * @param claimToken - the token escrowed in spigot to sell in trade
     * @param targetToken - the token borrow owed debt in and needs to buy. Always `credits[ids[0]].token`
     * @param swapTarget  - 0x exchange router address to call for trades
     * @param spigot      - spigot to claim from. Must be owned by adddress(this)
     * @param unused      - current amount of unused claimTokens
     * @param zeroExTradeData - 0x API data to use in trade to sell `claimToken` for target
     * @return (uint, uint) - (amount of target tokens bought, total unused claim tokens after trade)
     */
    function claimAndTrade(
        address claimToken,
        address targetToken,
        address payable swapTarget,
        address spigot,
        uint256 unused,
        bytes calldata zeroExTradeData
    )
        external 
        returns(uint256, uint256)
    {
        // can not trade into same token. causes double count for unused tokens
        if(claimToken == targetToken) { revert BadTradingPair(); }
        // snapshot token balances now to diff after trade executes
        uint256 oldClaimTokens = LoanLib.getBalance(claimToken);
        uint256 oldTargetTokens = LoanLib.getBalance(targetToken);
        
        // has to be called after we get balance
        uint256 claimed = ISpigot(spigot).claimEscrow(claimToken);

        trade(
            claimed + unused,
            claimToken,
            swapTarget,
            zeroExTradeData
        );
        
        // underflow revert ensures we have more tokens than we started with
        uint256 tokensBought = LoanLib.getBalance(targetToken) - oldTargetTokens;
        if(tokensBought == 0) { revert TradeFailed(); } // ensure tokens 
        uint256 newClaimTokens = LoanLib.getBalance(claimToken);
        // ideally we could use oracle to calculate # of tokens to receive
        // but sellToken might not have oracle. buyToken must have oracle

        
        emit TradeSpigotRevenue(
            claimToken,
            claimed,
            targetToken,
            tokensBought
        );

        // used reserve revenue to repay debt
        if(oldClaimTokens > newClaimTokens) {
          uint256 diff = oldClaimTokens - newClaimTokens;

          // used more tokens than we had in revenue reserves.
          // prevent borrower from pulling idle lender funds to repay other lenders
          if(diff > unused) revert UsedExcessTokens(claimToken,  unused); 
          // reduce reserves by consumed amount
          else return (
            tokensBought,
            unused - diff
          );
        } else { unchecked {
          // excess revenue in trade. store in reserves
          return (
            tokensBought,
            unused + (newClaimTokens - oldClaimTokens)
          );
        } }
    }

    function trade(
        uint256 amount,
        address sellToken,
        address payable swapTarget,
        bytes calldata zeroExTradeData
    ) 
        public
        returns(bool)
    {
        if (sellToken == Denominations.ETH) {
            // if claiming/trading eth send as msg.value to dex
            (bool success, ) = swapTarget.call{value: amount}(zeroExTradeData);
            if(!success) { revert TradeFailed(); }
        } else {
            IERC20(sellToken).approve(swapTarget, amount);
            (bool success, ) = swapTarget.call(zeroExTradeData);
            if(!success) { revert TradeFailed(); }
        }

        return true;
    }


    /**
     * @notice cleanup function when borrower this line ends 
     */
    function rollover(address spigot, address newLoan) external returns(bool) {
      require(ISpigot(spigot).updateOwner(newLoan));
      return true;
    }

}
