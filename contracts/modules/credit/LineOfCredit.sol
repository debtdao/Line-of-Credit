pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LoanLib} from "../../utils/LoanLib.sol";
import {MutualConsent} from "../../utils/MutualConsent.sol";
import {InterestRateCredit} from "../interest-rate/InterestRateCredit.sol";

import {IOracle} from "../../interfaces/IOracle.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";

contract LineOfCredit is ILineOfCredit, MutualConsent {
    using SafeERC20 for IERC20;

    address public immutable borrower;

    address public immutable arbiter;

    IOracle public immutable oracle;

    InterestRateCredit public immutable interestRate;

    uint256 public immutable deadline;

    bytes32[] public ids; // all active positions

    mapping(bytes32 => Credit) public credits; // id -> Credit

    // Loan Financials aggregated accross all existing  Credit
    LoanLib.STATUS public loanStatus;

    /**
   * @dev - Loan borrower and proposed lender agree on terms
            and add it to potential options for borrower to drawdown on
            Lender and borrower must both call function for MutualConsent to add credit position to Loan
   * @param oracle_ - price oracle to use for getting all token values
   * @param arbiter_ - neutral party with some special priviliges on behalf of borrower and lender
   * @param borrower_ - the debitor for all credit positions in this contract
   * @param ttl_ - time to live for line of credit contract across all lenders
  */
    constructor(
        address oracle_,
        address arbiter_,
        address borrower_,
        uint256 ttl_
    ) {
        oracle = IOracle(oracle_);
        arbiter = arbiter_;
        borrower = borrower_;
        deadline = block.timestamp + ttl_;
        interestRate = new InterestRateCredit();

        _updateLoanStatus(LoanLib.STATUS.ACTIVE);

        emit DeployLoan(oracle_, arbiter_, borrower_);
    }

    ///////////////
    // MODIFIERS //
    ///////////////

    modifier whileActive() {
        if(loanStatus != LoanLib.STATUS.ACTIVE) { revert NotActive(); }
        _;
    }

    modifier whileBorrowing() {
        if(ids.length == 0 || credits[ids[0]].principal == 0) { revert NotBorrowing(); }
        _;
    }

    modifier onlyBorrower() {
        if(msg.sender != borrower) { revert CallerAccessDenied(); }
        _;
    }

    /** @notice - mutualConsent but uses position to get lender address instead of passing it in directly */
    modifier mutualConsentById(address _signerOne, bytes32 id) {
      if(_mutualConsent(_signerOne, credits[id].lender))  {
        // Run whatever code needed 2/2 consent
        _;
      }
    }

    function healthcheck() external returns (LoanLib.STATUS) {
        return _updateLoanStatus(_healthcheck());
    }

    function _healthcheck() internal virtual returns (LoanLib.STATUS) {
        // if loan is in a final end state then do not run _healthcheck()
        if (
            loanStatus == LoanLib.STATUS.REPAID ||
            loanStatus == LoanLib.STATUS.INSOLVENT
        ) {
            return loanStatus;
        }

        // Liquidate if all lines of credit arent closed by end of term
        if (block.timestamp >= deadline && ids.length > 0) {
            emit Default(ids[0]); // can query all defaulted positions offchain once event picked up
            return LoanLib.STATUS.LIQUIDATABLE;
        }

        return LoanLib.STATUS.ACTIVE;
    }

    /**
     * @notice - Allow arbiter to signify that borrower is incapable of repaying debt permanently
     *           Recoverable funds for lender after declaring insolvency = deposit + interestRepaid - principal
     * @dev    - Needed for onchain impairment accounting e.g. updating ERC4626 share price
     *           MUST NOT have collateral left for call to succeed.
     *           Callable only by arbiter. 
     * @return bool - If borrower is insolvent or not
     */
    function declareInsolvent() external whileBorrowing returns(bool) {
        if(arbiter != msg.sender) { revert CallerAccessDenied(); }
        if(LoanLib.STATUS.LIQUIDATABLE != _updateLoanStatus(_healthcheck())) {
            revert NotLiquidatable();
        }

      // TODO for cwalk. Should we ensure only insolvent once ttl is over? 
      // Possible borrower fail anytime. no reson to prevent impairment until deadline

        if(_declareInsolvent()) {
            _updateLoanStatus(LoanLib.STATUS.INSOLVENT);
            return true;
        } else {
          return false;
        }
    }

    function _declareInsolvent() internal virtual returns(bool) {
        return true;
    }

    /**
  * @notice - Returns total credit obligation of borrower.
              Aggregated across all lenders.
              Denominated in USD 1e8.
  * @dev    - callable by anyone
  */
    function updateOutstandingDebt() external override returns (uint256, uint256) {
        return _updateOutstandingDebt();
    }

    function _updateOutstandingDebt()
        internal
        returns (uint256 principal, uint256 interest)
    {
        uint256 len = ids.length;
        if (len == 0) return (0, 0);

        Credit memory credit;
        for (uint256 i = 0; i < len; i++) {
            bytes32 id = ids[i];
            _accrueInterest(id);
            credit = credits[id];

            int256 price = oracle.getLatestAnswer(credit.token);

            principal += LoanLib.calculateValue(
                price,
                credit.principal,
                credit.decimals
            );
            interest += LoanLib.calculateValue(
                price,
                credit.interestAccrued,
                credit.decimals
            );
        }
    }

    /**
     * @notice - see _accrueInterest()
     * @dev    - callable by anyone
     */
    function accrueInterest() external override returns(bool) {
        uint256 len = ids.length;

        for (uint256 i = 0; i < len; i++) {
            _accrueInterest(ids[i]);
        }
        
        return true;
    }

    /**
   * @notice        - Loan borrower and proposed lender agree on terms
                    and add it to potential options for borrower to drawdown on
                    Lender and borrower must both call function for MutualConsent to add credit position to Loan
   * @dev           - callable by `lender` and `borrower
   * @param drate   - interest rate in bps on funds drawndown on LoC
   * @param frate   - interest rate in bps on all unused funds in LoC
   * @param amount  - amount of `token` to initially deposit
   * @param token   - the token to be lent out
   * @param lender  - address that will manage credit position 
  */
    function addCredit(
        uint128 drate,
        uint128 frate,
        uint256 amount,
        address token,
        address lender
    )
        external
        override
        whileActive
        mutualConsent(lender, borrower)
        returns (bytes32)
    {
        IERC20(token).safeTransferFrom(lender, address(this), amount);

        bytes32 id = _createCredit(lender, token, amount);

        require(interestRate.setRate(id, drate, frate));

        return id;
    }

    /**
    * @notice           - Let lender and borrower update rates on a aposition
    *                   - can set Rates even when LIQUIDATABLE for refinancing
    * @dev              - include lender in params for cheap gas and consistent API for mutualConsent
    * @dev              - callable by borrower or any lender
    * @param id - credit id that we are updating
    * @param drate      - new drawn rate
    * @param frate      - new facility rate
    
    */
    function setRates(
        bytes32 id,
        uint128 drate,
        uint128 frate
    )
      external
      override
      mutualConsentById(borrower, id)
      returns (bool)
    {
        _accrueInterest(id);
        require(interestRate.setRate(id, drate, frate));
        emit SetRates(id, drate, frate);
        return true;
    }


 /**
    * @notice           - Let lender and borrower increase total capacity of position
    *                   - can only increase while loan is healthy and ACTIVE.
    * @dev              - include lender in params for cheap gas and consistent API for mutualConsent
    * @dev              - callable by borrower    
    * @param id         - credit id that we are updating
    * @param amount     - amount to increase deposit / capaciity by
    */
    function increaseCredit(
        bytes32 id,
        uint256 amount
    )
      external
      override
      whileActive
      mutualConsentById(borrower, id)
      returns (bool)
    {
        _accrueInterest(id);

        IERC20(credits[id].token).safeTransferFrom(
          credits[id].lender,
          address(this),
          amount
        );
        credits[id].deposit += amount;
        
        emit IncreaseCredit(id, amount);

        return true;
    }

    ///////////////
    // REPAYMENT //
    ///////////////

    /**
    * @notice - Transfers enough tokens to repay entire credit position from `borrower` to Loan contract.
    * @dev - callable by borrower    
    */
    function depositAndClose()
        external
        override
        whileBorrowing
        onlyBorrower
        returns (bool)
    {
        bytes32 id = ids[0];
        _accrueInterest(id);

        uint256 totalOwed = credits[id].principal + credits[id].interestAccrued;

        // borrower deposits remaining balance not already repaid and held in contract
        IERC20(credits[id].token).safeTransferFrom(msg.sender, address(this), totalOwed);
        // clear the credit
        _repay(id, totalOwed);

        _close(id);
        return true;
    }

    /**
     * @dev - Transfers token used in credit position from msg.sender to Loan contract.
     * @dev - callable by anyone
     * @notice - see _repay() for more details
     * @param amount - amount of `token` in `id` to pay back
     */
    function depositAndRepay(uint256 amount)
        external
        override
        whileBorrowing
        returns (bool)
    {
        bytes32 id = ids[0];
        _accrueInterest(id);

        require(amount <= credits[id].principal + credits[id].interestAccrued);

        IERC20(credits[id].token).safeTransferFrom(msg.sender, address(this), amount);

        _repay(id, amount);
        return true;
    }

    ////////////////////
    // FUND TRANSFERS //
    ////////////////////

    /**
     * @dev - Transfers tokens from Loan to lender.
     *        Only allowed to withdraw tokens not already lent out (prevents bank run)
     * @dev - callable by lender on `id`
     * @param id - the credit position to draw down credit on
     * @param amount - amount of tokens borrower wants to take out
     */
    function borrow(bytes32 id, uint256 amount)
        external
        override
        whileActive
        onlyBorrower
        returns (bool)
    {
        _accrueInterest(id);
        Credit memory credit = credits[id];

        if(amount > credit.deposit - credit.principal) { revert NoLiquidity() ; }

        credit.principal += amount;

        credits[id] = credit;

        if(_updateLoanStatus(_healthcheck()) != LoanLib.STATUS.ACTIVE) { 
            revert NotActive();
        }

        IERC20(credit.token).safeTransfer(borrower, amount);

        emit Borrow(id, amount);

        _sortIntoQ(id);

        return true;
    }

    /**
     * @dev - Transfers tokens from Loan to lender.
     *        Only allowed to withdraw tokens not already lent out (prevents bank run)
     * @dev - callable by lender on `id`
     * @param id -the credit position to pay down credit on and close
     * @param amount - amount of tokens lnder would like to withdraw (withdrawn amount may be lower)
     */
    function withdraw(bytes32 id, uint256 amount)
        external
        override
        returns (bool)
    {
        Credit memory credit = credits[id];
        
        if(msg.sender != credit.lender) { revert CallerAccessDenied(); }

        _accrueInterest(id);

        if(amount > credit.deposit + credit.interestRepaid - credit.principal) {
          revert NoLiquidity();
        }

        if (amount > credit.interestRepaid) {
            amount -= credit.interestRepaid;

            // emit events before seeting to 0
            emit WithdrawDeposit(id, amount);
            emit WithdrawProfit(id, credit.interestRepaid);

            credit.deposit -= amount;
            credit.interestRepaid = 0;
        } else {
            credit.interestRepaid -= amount;
            emit WithdrawProfit(id, amount);
        }

        credits[id] = credit;

        IERC20(credit.token).safeTransfer(credit.lender, amount);

        return true;
    }

    /**
     * @dev - Deletes credit position preventing any more borrowing.
     *      - Only callable by borrower or lender for credit position
     *      - Requires that the credit has already been paid off
     * @dev - callable by `borrower`
     * @param id -the credit position to close
     */
    function close(bytes32 id) external override returns (bool) {
        address b = borrower;         // gas savings
        if(msg.sender != credits[id].lender && msg.sender != b) {
          revert CallerAccessDenied();
        }

        // ensure all money owed is accounted for
        _accrueInterest(id);
        uint256 facilityFee = credits[id].interestAccrued;
        if(facilityFee > 0) {
          // only allow repaying interest since they are skipping repayment queue.
          // If principal still owed, _close() MUST fail
          IERC20( credits[id].token).safeTransferFrom(b, address(this), facilityFee);
          _repay(id, facilityFee);
        }

        _close(id);

        return true;
    }

    //////////////////////
    //  Internal  funcs //
    //////////////////////

    function _updateLoanStatus(LoanLib.STATUS status)
        internal
        returns (LoanLib.STATUS)
    {
        if (loanStatus == status) return loanStatus;
        loanStatus = status;
        emit UpdateLoanStatus(uint256(status));
        return status;
    }

    function _createCredit(
        address lender,
        address token,
        uint256 amount
    ) internal returns (bytes32 id) {
        id = LoanLib.computePositionId(address(this), lender, token);

        // MUST not double add position. otherwise we can not _close()
        if(credits[id].lender != address(0)) { revert PositionExists(); }

        int price = IOracle(oracle).getLatestAnswer(token);
        if(price <= 0 ) { revert NoTokenPrice(); }

        (bool passed, bytes memory result) = token.call(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimals = !passed ? 18 : abi.decode(result, (uint8));
        
        credits[id] = Credit({
            lender: lender,
            token: token,
            decimals: decimals,
            deposit: amount,
            principal: 0,
            interestAccrued: 0,
            interestRepaid: 0
        });

        ids.push(id); // add lender to end of repayment queue

        emit AddCredit(lender, token, amount, id);

        return id;
    }

  /**
   * @dev - Reduces `principal` and/or `interestAccrued` on credit position, increases lender's `deposit`.
            Reduces global USD principal and interestUsd values.
            Expects checks for conditions of repaying and param sanitizing before calling
            e.g. early repayment of principal, tokens have actually been paid by borrower, etc.
   * @param id - credit position struct with all data pertaining to loan
   * @param amount - amount of token being repaid on credit position
  */
    function _repay(bytes32 id, uint256 amount)
        internal
        returns (bool)
    {
        Credit memory credit = credits[id];
        
        if (amount <= credit.interestAccrued) {
            credit.interestAccrued -= amount;
            credit.interestRepaid += amount;
            emit RepayInterest(id, amount);
        } else {
            uint256 principalPayment = amount - credit.interestAccrued;

            emit RepayInterest(id, credit.interestAccrued);
            emit RepayPrincipal(id, principalPayment);

            // update individual credit position denominated in token
            credit.principal -= principalPayment;
            credit.interestRepaid += credit.interestAccrued;
            credit.interestAccrued = 0;

            // if credit fully repaid then remove lender from repayment queue
            if (credit.principal == 0) ids = LoanLib.stepQ(ids);
        }

        credits[id] = credit;

        return true;
    }

  /**
   * @dev - Loops over all credit positions, calls InterestRate module with position data,
            then updates `interestAccrued` on position with returned data.
            Also updates global USD values for `interestUsd`.
            Can only be called when loan is not in distress
  */
    function _accrueInterest(bytes32 id)
        internal
        returns (uint256 accruedToken)
    {
        // get token demoninated interest accrued
        accruedToken = interestRate.accrueInterest(
            id,
            credits[id].principal,
            credits[id].deposit
        );

        // update credits balance
        credits[id].interestAccrued += accruedToken;

        emit InterestAccrued(id, accruedToken);

        return accruedToken;
    }

    /**
     * @notice - checks that credit is fully repaid and remvoes from available lines of credit.
     * @dev deletes Credit storage. Store any data u might need later in call before _close()
     */
    function _close(bytes32 id) internal virtual returns (bool) {
        Credit memory credit = credits[id];

        if(credit.principal > 0) { revert CloseFailedWithPrincipal(); }

        // return the lender's deposit
        if (credit.deposit > 0) {
            IERC20(credit.token).safeTransfer(
                credit.lender,
                credit.deposit + credit.interestRepaid
            );
        }

        delete credits[id]; // gas refunds

        // remove from active list
        ids = LoanLib.removePosition(ids, id);

        // brick loan contract if all positions closed
        if (ids.length == 0) {
            _updateLoanStatus(LoanLib.STATUS.REPAID);
        }

        emit CloseCreditPosition(id);

        return true;
    }

    /**
     * @notice - Insert `p` into the next availble FIFO position in repayment queue
               - once earliest slot is found, swap places with `p` and position in slot.
     * @param p - position id that we are trying to find appropriate place for
     * @return
     */
    function _sortIntoQ(bytes32 p) internal returns (bool) {
        uint256 lastSpot = ids.length - 1;
        uint256 nextQSpot = lastSpot;
        bytes32 id;
        for (uint256 i = 0; i <= lastSpot; i++) {
            id = ids[i];
            if (p != id) {
                if (
                  nextQSpot != lastSpot ||  // position already found. skip to find `p` asap
                  credits[id].principal > 0 //`id` should be placed before `p` 
                ) continue;
                nextQSpot = i;              // index of first undrawn line found
            } else {
                if(nextQSpot == lastSpot) return true; // nothing to update
                // swap positions
                ids[i] = ids[nextQSpot];    // id put into old `p` position
                ids[nextQSpot] = p;       // p put at target index
                return true; 
            }
        }
    }
}
