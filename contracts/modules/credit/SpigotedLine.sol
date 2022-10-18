pragma solidity ^0.8.9;

import {Denominations} from "chainlink/Denominations.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {LineOfCredit} from "./LineOfCredit.sol";
import {LineLib} from "../../utils/LineLib.sol";
import {CreditLib} from "../../utils/CreditLib.sol";
import {SpigotedLineLib} from "../../utils/SpigotedLineLib.sol";
import {MutualConsent} from "../../utils/MutualConsent.sol";
import {ISpigot} from "../../interfaces/ISpigot.sol";
import {ISpigotedLine} from "../../interfaces/ISpigotedLine.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract SpigotedLine is ISpigotedLine, LineOfCredit, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ISpigot public immutable spigot;

    // @notice 0x exchange router to trade revenue tokens from a Spigot for credit tokens
    address payable public immutable swapTarget;

    // @notice % of revenue tokens to take from Spigot if the Line of Credit  is healthy
    uint8 public immutable defaultRevenueSplit;

    // @notice Credit Tokens we bought from Revenue Tokens but didn't yet use to repay debt
    // @dev needed because the Line of Credit might have same token held in contract as being bought/sold
    mapping(address => uint256) private unusedTokens;

    /**
     * @notice - The SpigotedLine is a LineofCredit contract with additional functionality for integrating with a Spigot
     *              using Borrower revenue streams to repay debt
     * @param oracle_ - price oracle to use for getting all token values
     * @param arbiter_ - neutral party with some special priviliges on behalf of borrower and lender
     * @param borrower_ - the debitor for all credit positions in this contract
     * @param swapTarget_ - 0x protocol exchange address to send calldata for trades to exchange revenue tokens for credit tokens
     * @param ttl_ - time to live for line of credit contract across all lenders set at deployment in order to set the term/expiry date
     * @param defaultRevenueSplit_ - The initial % of Revenue Tokens that the Spigot sends to the Owner if the Line of Credit is healthy.
     */
    constructor(
        address oracle_,
        address arbiter_,
        address borrower_,
        address spigot_,
        address payable swapTarget_,
        uint256 ttl_,
        uint8 defaultRevenueSplit_
    ) LineOfCredit(oracle_, arbiter_, borrower_, ttl_) {
        require(defaultRevenueSplit_ <= SpigotedLineLib.MAX_SPLIT);

        spigot = ISpigot(spigot_);
        defaultRevenueSplit = defaultRevenueSplit_;
        swapTarget = swapTarget_;
    }

    function _init() internal virtual override (LineOfCredit) returns (LineLib.STATUS) {
        if (spigot.owner() != address(this)) return LineLib.STATUS.UNINITIALIZED;
        return LineOfCredit._init();
    }

    function unused(address token) external view returns (uint256) {
        return unusedTokens[token];
    }

    function _canDeclareInsolvent() internal virtual override returns (bool) {
        return SpigotedLineLib.canDeclareInsolvent(address(spigot), arbiter);
    }

    /**
     * @notice - Claims revenue tokens from the Spigot, trades them for credit tokens via a Dex (Ox) and sends the credit tokens to a Lender to repay debt.
     * @dev    - callable `borrower` + `lender`
     * @notice see _repay() for more details
     * @param claimToken - The Revenue Token escrowed by Spigot to claim and use to repay debt
     * @param zeroExTradeData - data generated by the 0x dex API to trade `claimToken` against their exchange contract
     */
    function claimAndRepay(address claimToken, bytes calldata zeroExTradeData)
        external
        whileBorrowing
        nonReentrant
        returns (uint256)
    {
        bytes32 id = ids[0];
        Credit memory credit = credits[id];
        credit = _accrue(credit, id);

        if (msg.sender != borrower && msg.sender != credit.lender) {
            revert CallerAccessDenied();
        }

        uint256 newTokens = claimToken == credit.token
            ? spigot.claimEscrow(claimToken) // same asset. dont trade
            : _claimAndTrade( // trade revenue token for debt obligation
            claimToken, credit.token, zeroExTradeData);

        // TODO abstract this into library func

        uint256 repaid = newTokens + unusedTokens[credit.token];
        uint256 debt = credit.interestAccrued + credit.principal;

        // cap payment to debt value
        if (repaid > debt) repaid = debt;
        // update unused amount based on usage
        if (repaid > newTokens) {
            // using bought + unused to repay line
            unusedTokens[credit.token] -= repaid - newTokens;
        } else {
            //  high revenue and bought more than we need
            unusedTokens[credit.token] += newTokens - repaid;
        }

        credits[id] = _repay(credit, id, repaid);

        emit RevenuePayment(claimToken, repaid);
    }

    // Allows a balance of unusedTokens (credit tokens that have already been claimed/traded) to be repaid to a Lender
    // i.e. without first claiming any new revenue tokens from the Spigot and then converting them to credit tokens

    function useAndRepay(uint256 amount) external whileBorrowing returns (bool) {
        bytes32 id = ids[0];
        Credit memory credit = credits[id];
        if (msg.sender != borrower && msg.sender != credit.lender) {
            revert CallerAccessDenied();
        }
        require(amount <= unusedTokens[credit.token]);
        unusedTokens[credit.token] -= amount;

        credits[id] = _repay(_accrue(credit, id), id, amount);

        return true;
    }

    /**
     * @notice see notice for same function in SpigotedLineLib.sol [Bob - why is this function 'detailed' twice?]
     * @dev ensures first token in repayment queue is being bought
     * @dev    - callable `arbiter` + `borrower`
     * @param claimToken - The revenue token escrowed in the Spigot to sell in trade
     * @param zeroExTradeData - 0x API data to use in trade to sell `claimToken` for `credits[ids[0]]`
     * returns - amount of credit tokens bought
     */
    function claimAndTrade(address claimToken, bytes calldata zeroExTradeData)
        external
        whileBorrowing
        nonReentrant
        returns (uint256)
    {
        require(msg.sender == borrower);

        address targetToken = credits[ids[0]].token;
        uint256 newTokens = claimToken == targetToken
            ? spigot.claimEscrow(claimToken) // same asset. dont trade
            : _claimAndTrade( // trade revenue token for debt obligation
            claimToken, targetToken, zeroExTradeData);

        // add bought tokens to unused balance
        unusedTokens[targetToken] += newTokens;
        return newTokens;
    }

    /**
     * [Bob - why is this function 'detailed' twice?]
     * @notice  Allows revenue tokens in 'escrowed' to be traded for credit tokens that aren't yet used to repay debt.
     * @dev MUST trade all available claim tokens to target
     * @dev    priviliged internal function
     * @param claimToken - The revenue token escrowed in the Spigot to sell in trade
     * @param targetToken - The credit token that needs to be bought in order to pat down debt. Always `credits[ids[0]].token`
     * @param zeroExTradeData - 0x API data to use in trade to sell `claimToken` for target
     * returns - amount of target tokens bought
     */

    function _claimAndTrade(address claimToken, address targetToken, bytes calldata zeroExTradeData)
        internal
        returns (uint256)
    {
        (uint256 tokensBought, uint256 totalUnused) = SpigotedLineLib.claimAndTrade(
            claimToken, targetToken, swapTarget, address(spigot), unusedTokens[claimToken], zeroExTradeData
        );

        // we dont use revenue after this so can store now
        unusedTokens[claimToken] = totalUnused;
        return tokensBought;
    }

    //  SPIGOT OWNER FUNCTIONS

    /**
     * @notice Changes the revenue split between the Treasury and the Line (Owner) based upon the status of the Line of Credit
     * @dev    - callable `arbiter` + `borrower`
     * @param revenueContract - spigot to update
     * @return whether or not split was updated
     */
    function updateOwnerSplit(address revenueContract) external returns (bool) {
        return SpigotedLineLib.updateSplit(
            address(spigot), revenueContract, _updateStatus(_healthcheck()), defaultRevenueSplit
        );
    }

    /**
     * @notice - allow Line (Owner) to add new revenue streams to repay credit
     * @dev    - see Spigot.addSpigot()
     * @dev    - callable `arbiter` + `borrower`
     */
    function addSpigot(address revenueContract, ISpigot.Setting calldata setting)
        external
        mutualConsent(arbiter, borrower)
        returns (bool)
    {
        return spigot.addSpigot(revenueContract, setting);
    }

    /**
     * @notice - Sets or resets the whitelisted functions that a Borrower [Operator] is allowed to perform on the revenue generating contracts
     *             whilst the Spigot is attached.  Triggers updateWhitelistedFunction() in Spigot.sol
     * @dev    - see Spigot.updateWhitelistedFunction()
     * @dev    - callable `arbiter` ONLY
     */
    function updateWhitelist(bytes4 func, bool allowed) external returns (bool) {
        require(msg.sender == arbiter);
        return spigot.updateWhitelistedFunction(func, allowed);
    }

    /**
     * @notice - Transfers ownership of the entire Spigot from its then Owner to either the Borrower (if a Line of Credit has been been fully repaid)
     *            or to the Arbiter (if the Line of Credit is liquidatable).
     * @dev    - callable by anyone
     * @return - whether or not a Spigot was released
     */
    function releaseSpigot() external returns (bool) {
        return SpigotedLineLib.releaseSpigot(address(spigot), _updateStatus(_healthcheck()), borrower, arbiter);
    }

    /**
     * @notice - sends unused tokens to borrower if repaid or arbiter if liquidatable
     *          -  doesnt send tokens out if line is unpaid but healthy
     * @dev    - callable by anyone
     * @param token - token to take out
     */
    function sweep(address to, address token) external nonReentrant returns (uint256) {
        uint256 amount = unusedTokens[token];
        delete unusedTokens[token];

        bool success = SpigotedLineLib.sweep(to, token, amount, _updateStatus(_healthcheck()), borrower, arbiter);

        return success ? amount : 0;
    }

    // allow claiming/trading in ETH
    receive() external payable {}
}
