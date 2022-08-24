pragma solidity 0.8.9;

import { ISpigotedLine } from "../interfaces/ISpigotedLine.sol";
import { LineLib } from "../utils/LineLib.sol";
import { SpigotLib, SpigotState } from "../utils/SpigotLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";

library SpigotedLineLib {

    // max revenue to take from spigot if line is in distress
    uint8 constant MAX_SPLIT = 100;

    error NoSpigot();

    error TradeFailed();

    error BadTradingPair();

    error CallerAccessDenied();
    
    error ReleaseSpigotFailed();

    error NotInsolvent(address module);

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
     * @param unused      - current amount of unused claimTokens
     * @param zeroExTradeData - 0x API data to use in trade to sell `claimToken` for target
     * @return (uint, uint) - (amount of target tokens bought, total unused claim tokens after trade)
     */
    function claimAndTrade(
        SpigotState storage self,
        address claimToken,
        address targetToken,
        address payable swapTarget,
        uint256 unused,
        bytes calldata zeroExTradeData
    )
        external 
        returns(uint256, uint256)
    {
        // can not trade into same token. causes double count for unused tokens
        if(claimToken == targetToken) { revert BadTradingPair(); }

        // snapshot token balances now to diff after trade executes
        uint256 oldClaimTokens = LineLib.getBalance(claimToken);
        uint256 oldTargetTokens = LineLib.getBalance(targetToken);
        
        // claim has to be called after we get balance
        uint256 claimed = SpigotLib.claimEscrow(self, claimToken);

        trade(
            claimed + unused,
            claimToken,
            swapTarget,
            zeroExTradeData
        );
        
        // underflow revert ensures we have more tokens than we started with
        uint256 tokensBought = LineLib.getBalance(targetToken) - oldTargetTokens;

        if(tokensBought == 0) { revert TradeFailed(); } // ensure tokens bought

        uint256 newClaimTokens = LineLib.getBalance(claimToken);

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
    function rollover(SpigotState storage self, address newLine) external returns(bool) {
      require(SpigotLib.updateOwner(self, newLine));
      return true;
    }

    function canDeclareInsolvent(SpigotState storage self, address arbiter) external view returns (bool) {
            // Must have called releaseSpigot() and sold off protocol / revenue streams already
      address owner_ = SpigotLib.owner(self);
      if(
        address(this) == owner_ ||
        arbiter == owner_
      ) { revert NotInsolvent(address(SpigotLib)); }
      // no additional logic in LineOfCredit to include
      return true;
    }


    /**
     * @notice changes the revenue split between borrower treasury and lan repayment based on line health
     * @dev    - callable `arbiter` + `borrower`
     * @param revenueContract - spigot to update
     * @return whether or not split was updated
     */
    function updateSplit(SpigotState storage self, address revenueContract, LineLib.STATUS status, uint8 defaultSplit) external returns (bool) {
        (,uint8 split,  ,bytes4 transferFunc) = SpigotLib.getSetting(self, revenueContract);

        if(transferFunc == bytes4(0)) { revert NoSpigot(); }

        if(status == LineLib.STATUS.ACTIVE && split != defaultSplit) {
            // if line is healthy set split to default take rate
            return SpigotLib.updateOwnerSplit(self, revenueContract, defaultSplit);
        } else if (status == LineLib.STATUS.LIQUIDATABLE && split != MAX_SPLIT) {
            // if line is in distress take all revenue to repay line
            return SpigotLib.updateOwnerSplit(self, revenueContract, MAX_SPLIT);
        }

        return false;
    }


    /**

   * @notice -  transfers revenue streams to borrower if repaid or arbiter if liquidatable
             -  doesnt transfer out if line is unpaid and/or healthy
   * @dev    - callable by anyone 
   * @return - whether or not spigot was released
  */
    function releaseSpigot(SpigotState storage self, LineLib.STATUS status, address borrower, address arbiter) external returns (bool) {
        if (status == LineLib.STATUS.REPAID) {
          if (msg.sender != borrower) { revert CallerAccessDenied(); } 
          if(!SpigotLib.updateOwner(self, borrower)) { revert ReleaseSpigotFailed(); }
          return true;
        }

        if (status == LineLib.STATUS.LIQUIDATABLE) {
          if (msg.sender != arbiter) { revert CallerAccessDenied(); } 
          if(!SpigotLib.updateOwner(self, arbiter)) { revert ReleaseSpigotFailed(); }
          return true;
        }

        return false;
    }


        /**

   * @notice -  transfers revenue streams to borrower if repaid or arbiter if liquidatable
             -  doesnt transfer out if line is unpaid and/or healthy
   * @dev    - callable by anyone 
   * @return - whether or not spigot was released
  */
    function sweep(address to, address token, uint256 amount, LineLib.STATUS status, address borrower, address arbiter) external returns (bool) {
        if(amount == 0) { revert UsedExcessTokens(token, 0); }

        if (status == LineLib.STATUS.REPAID) {
            if (msg.sender != borrower) { revert CallerAccessDenied(); } 
            return LineLib.sendOutTokenOrETH(token, to, amount);

        }

        if (status == LineLib.STATUS.LIQUIDATABLE) {
            if (msg.sender != arbiter) { revert CallerAccessDenied(); } 
            return LineLib.sendOutTokenOrETH(token, to, amount);
        }

        return false;
    }
}
