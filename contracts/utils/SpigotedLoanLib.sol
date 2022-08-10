import { ISpigot } from "../interfaces/ISpigot.sol";
import { ISpigotedLoan } from "../interfaces/ISpigotedLoan.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library SpigotedLoanLib {
    error TradeFailed();
    event TradeSpigotRevenue(
        address indexed revenueToken,
        uint256 revenueTokenAmount,
        address indexed debtToken,
        uint256 indexed debtTokensBought
    );

    function claimAndTrade(
        address claimToken,
        address targetToken,
        address swapTarget,
        address spigot,
        uint256 unused,
        bytes calldata zeroExTradeData
    ) 
        external
        returns(uint256 tokensBought, uint256 totalUnused)
    {
        uint256 existingClaimTokens = IERC20(claimToken).balanceOf(address(this));
        uint256 existingTargetTokens = IERC20(targetToken).balanceOf(address(this));

        uint256 tokensClaimed = ISpigot(spigot).claimEscrow(claimToken);

        if (claimToken == address(0)) {
            // if claiming/trading eth send as msg.value to dex
            (bool success, ) = swapTarget.call{value: tokensClaimed}(zeroExTradeData);
            if(!success) { revert TradeFailed(); }
        } else {
            // approve exact amount so other tokens in contract get used e.g. lender funds
            IERC20(claimToken).approve(swapTarget, unused + tokensClaimed);
            (bool success, ) = swapTarget.call(zeroExTradeData);
            if(!success) { revert TradeFailed(); }
        }

        uint256 targetTokens = IERC20(targetToken).balanceOf(address(this));

        // ideally we could use oracle to calculate # of tokens to receive
        // but claimToken might not have oracle. targetToken must have oracle

        // underflow revert ensures we have more tokens than we started with
        tokensBought = targetTokens - existingTargetTokens;

        emit TradeSpigotRevenue(
            claimToken,
            tokensClaimed,
            targetToken,
            tokensBought
        );

        uint256 remainingClaimTokens = IERC20(claimToken).balanceOf(address(this));
        // use reserve revenue to repay debt
        if(existingClaimTokens > remainingClaimTokens) {
          uint256 diff = existingClaimTokens - remainingClaimTokens;
          // used more tokens than we had in unused
          if(diff > unused) revert TradeFailed(); 
          else totalUnused = unused - diff;
        } else {
          // didnt sell all revenue in trade
          totalUnused = unused + (remainingClaimTokens - existingClaimTokens);
        }

    }
}
