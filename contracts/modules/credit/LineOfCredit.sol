pragma solidity ^0.8.9;

import { Denominations } from "chainlink/Denominations.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20}  from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {LineLib} from "../../utils/LineLib.sol";
import {CreditLib} from "../../utils/CreditLib.sol";
import {CreditListLib} from "../../utils/CreditListLib.sol";
import {MutualConsent} from "../../utils/MutualConsent.sol";
import {InterestRateCredit} from "../interest-rate/InterestRateCredit.sol";

import {IOracle} from "../../interfaces/IOracle.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";

contract LineOfCredit is ILineOfCredit, MutualConsent {
    using SafeERC20 for IERC20;

    using CreditListLib for bytes32[];

    uint256 public immutable deadline;

    address public immutable borrower;

    address public immutable arbiter;

    IOracle public immutable oracle;

    InterestRateCredit public immutable interestRate;

    uint256 private count; // amount of open credit lines on a Line of Credit facility. ids.length includes null items

    bytes32[] public ids; // all open credit lines

    mapping(bytes32 => Credit) public credits; // id -> Reference ID for a credit line provided by a single Lender for a given token on a Line of Credit

    // Line Financials aggregated accross all existing  Credit
    LineLib.STATUS public status;

    /**
   * @notice - how to deploy a Line of Credit
   * @dev - A Borrower and a first Lender agree on terms then the Borrower deploys the contract using the contructor below
            Later, both Lender and borrower must call _mutualConsent during addCredit() to add actually deposit funds
   * @param oracle_ - The price oracle to use for getting all token values
   * @param arbiter_ - A neutral party with some special priviliges on behalf of Borrower and Lender
   * @param borrower_ - the debitor for all credit lines in this contract
   * @param ttl_ - the time to live for all credit lines for the Line of Credit facility (sets the term of the Line of Credit)
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
        deadline = block.timestamp + ttl_;  //the deadline is the term/maturity/expiry date of the Line of Credit facility
        interestRate = new InterestRateCredit();

        emit DeployLine(oracle_, arbiter_, borrower_);
    }

    function init() external virtual returns(LineLib.STATUS) {
      if(status != LineLib.STATUS.UNINITIALIZED) { revert AlreadyInitialized(); }
      return _updateStatus(_init());
    }

    function _init() internal virtual returns(LineLib.STATUS) {
       // If no collateral or Spigot then Line of Credit is immediately active
      return LineLib.STATUS.ACTIVE;
    }

    ///////////////
    // MODIFIERS //
    ///////////////

    modifier whileActive() {
        if(status != LineLib.STATUS.ACTIVE) { revert NotActive(); }
        _;
    }

    modifier whileBorrowing() {
        if(count == 0 || credits[ids[0]].principal == 0) { revert NotBorrowing(); }
        _;
    }

    modifier onlyBorrower() {
        if(msg.sender != borrower) { revert CallerAccessDenied(); }
        _;
    }

    /** @notice - in _mutualConsent, uses the credit line id to get Lender address instead of passing it in directly */
    modifier mutualConsentById(address _signerOne, bytes32 id) {
      if(_mutualConsent(_signerOne, credits[id].lender))  {
        // Run whatever code needed 2/2 consent
        _;
      }
    }

    function healthcheck() external returns (LineLib.STATUS) {
        // can only check if the line has been initialized
        require(uint(status) >= uint( LineLib.STATUS.ACTIVE));
        return _updateStatus(_healthcheck());
    }

    /** 
     * @notice - getter for amount of active ids + total ids in list
     * @return - (uint, uint) - active credit lines, total length
    */
    function counts() external view returns (uint256, uint256) {
        return (count, ids.length);
    }

    function _healthcheck() internal virtual returns (LineLib.STATUS) {
        // if line is in a final end state then do not run _healthcheck()
        LineLib.STATUS s = status;
        if (
            s == LineLib.STATUS.REPAID ||               // end state - good
            s == LineLib.STATUS.INSOLVENT               // end state - bad
        ) {
            return status;
        }

        // Liquidate if all credit lines aren't closed by deadline
        if (block.timestamp >= deadline && count > 0) {
            emit Default(ids[0]); // can query all defaulted positions offchain once event picked up
            return LineLib.STATUS.LIQUIDATABLE;
        }

        return LineLib.STATUS.ACTIVE;
    }

    /**
     * @notice - Allow the Arbiter to signify that the Borrower is incapable of repaying debt permanently
     *           Recoverable funds for Lender after declaring insolvency = deposit + interestRepaid - principal
     * @dev    - Needed for onchain impairment accounting e.g. updating ERC4626 share price
     *           MUST NOT have collateral left for call to succeed. Any collateral should already have been liquidated.
     *           Callable only by Arbiter. 
     * @return bool - If Borrower is insolvent or not
     */
    function declareInsolvent() external whileBorrowing returns(bool) {
        if(arbiter != msg.sender) { revert CallerAccessDenied(); }
        if(LineLib.STATUS.LIQUIDATABLE != _updateStatus(_healthcheck())) {
            revert NotLiquidatable();
        }

        if(_canDeclareInsolvent()) {
            _updateStatus(LineLib.STATUS.INSOLVENT);
            return true;
        } else {
          return false;
        }
    }

    function _canDeclareInsolvent() internal virtual returns(bool) {
        // logic updated in Spigoted and Escrowed lines
        return true;
    }

    /**
  * @notice - Returns the total debt of a Borrower across all credit lines and to all Lenders 
              aggregated across all lenders on the Line of Credit in USD
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

        bytes32 id;
        address oracle_ = address(oracle);  // gas savings
        address interestRate_ = address(interestRate);
        
        for (uint256 i; i < len; ++i) {
            id = ids[i];

            // gas savings. capped to len. inc before early continue
            

            // null element in array
            if(id == bytes32(0)) { continue; }

            (Credit memory c, uint256 _p, uint256 _i) = CreditLib.getOutstandingDebt(
              credits[id],
              id,
              oracle_,
              interestRate_
            );
            // update aggregate usd value
            principal += _p;
            interest += _i;
            // update credit line data
            credits[id] = c;
        }
    }

    /**
     * @dev - Loops over all credit lines, calls InterestRateCredit with the id data,
            then updates 'interestAccrued'.  Runs any time a change is made that affects the amount owed.
    */
    function accrueInterest() external override returns(bool) {
        uint256 len = ids.length;
        bytes32 id;
        for (uint256 i; i < len; ++i) {
          id = ids[i];
          Credit memory credit = credits[id];
          credits[id] = _accrue(credit, id);
          
        }
        
        return true;
    }

    function _accrue(Credit memory credit, bytes32 id) internal returns(Credit memory) {
      return CreditLib.accrue(credit, id, address(interestRate));
    }

    /**
   * @notice        After a Borrower and a Lender have agreed terms, both Lender and borrower must call _mutualConsent during addCredit()
                    to add actually deposit funds to a credit line
   * @dev           - callable by `lender` and `borrower
   * @param drate   - The interest rate charged to a Borrower on borrowed / drawn down funds in bps, 4 decimals
   * @param frate   - The interest rate charged to a Borrower on the remaining funds available, but not yet drawn down 
                      (rate charged on the available headroom) in bps, 4 decimals
   * @param amount  - The amount of Credit Token to initially deposit by the Lender
   * @param token   - The Credit Token, i.e. the token to be lent out
   * @param lender  - The address that will manage credit line
  */
    function addCredit(uint128 drate,uint128 frate,uint256 amount,address token,address lender)
        external
        payable
        override
        whileActive
        mutualConsent(lender, borrower)
        returns (bytes32)
    {
        LineLib.receiveTokenOrETH(token, lender, amount);

        bytes32 id = _createCredit(lender, token, amount);

        require(interestRate.setRate(id, drate, frate));
        
        return id;
    }

    /**
    * @notice           - Lets Lender and Borrower update rates on a credit line
    *                   - can do so even when LIQUIDATABLE for the purpose of refinancing and/or renego
    * @dev              - include lender in params for cheap gas and consistent API for mutualConsent
    * @dev              - callable by Borrower or Lender
    * @param id         - credit line id that we are updating
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
        Credit memory credit = credits[id];
        credits[id] = _accrue(credit, id);
        require(interestRate.setRate(id, drate, frate));
        emit SetRates(id, drate, frate);
        return true;
    }


 /**
    * @notice           - Lets a Lender and a Borrower increase the credit limit on a Line if the line status is 'active'
    * @dev              - include lender in params for cheap gas and consistent API for mutualConsent
    * @dev              - callable by borrower    
    * @param id         - credit line id that we are updating
    * @param amount     - amount to deposit by the Lender
    */
    function increaseCredit(bytes32 id, uint256 amount)
      external
      payable
      override
      whileActive
      mutualConsentById(borrower, id)
      returns (bool)
    {
        Credit memory credit = credits[id];
        credit = _accrue(credit, id);

        credit.deposit += amount;
        
        credits[id] = credit;

        LineLib.receiveTokenOrETH(credit.token, credit.lender, amount);

        emit IncreaseCredit(id, amount);

        return true;
    }

    ///////////////
    // REPAYMENT //
    ///////////////

    /**
    * @notice - A Borrower deposits enough tokens to repay and close a credit line.
    * @dev - callable by borrower    
    */
    function depositAndClose()
        external
        payable
        override
        whileBorrowing
        onlyBorrower
        returns (bool)
    {
        bytes32 id = ids[0];
        Credit memory credit = credits[id];
        credit = _accrue(credit, id);

        uint256 totalOwed = credit.principal + credit.interestAccrued;

        // Borrower deposits the remaining balance not already repaid and already available to be withdrawn by the Lender
        LineLib.receiveTokenOrETH(credit.token, msg.sender, totalOwed);

        // Borrower clears the debt then closes and deletes the credit line
        _close(_repay(credit, id, totalOwed), id);

        return true;
    }

    /**
     * @dev - Transfers token used in credit line id from msg.sender to Line contract.
     * @dev - Available for anyone to deposit Credit Tokens to be available to be withdrawn by Lenders 
     * @notice - see _repay() for more details
     * @param amount - amount of `token` in `id` to pay back
     */
    function depositAndRepay(uint256 amount)
        external
        payable
        override
        whileBorrowing
        returns (bool)
    {
        bytes32 id = ids[0];
        Credit memory credit = credits[id];
        credit = _accrue(credit, id);

        require(amount <= credit.principal + credit.interestAccrued);

        credits[id] = _repay(credit, id, amount);

        LineLib.receiveTokenOrETH(credit.token, msg.sender, amount);

        return true;
    }

    ////////////////////
    // FUND TRANSFERS //
    ////////////////////

    /**
     * @dev - Transfers tokens from a credit line id to a Borrower
     * @dev - callable by borrower on `id`
     * @param id - the credit line to draw down on
     * @param amount - amount of tokens the borrower wants to withdraw
     */
    function borrow(bytes32 id, uint256 amount)
        external
        override
        whileActive
        onlyBorrower
        returns (bool)
    {
        Credit memory credit = credits[id];
        credit = _accrue(credit, id);

        if(amount > credit.deposit - credit.principal) { revert NoLiquidity() ; }

        credit.principal += amount;

        credits[id] = credit; // save new debt before healthcheck

        if(_updateStatus(_healthcheck()) != LineLib.STATUS.ACTIVE) { 
            revert NotActive();
        }

        credits[id] = credit;

        LineLib.sendOutTokenOrETH(credit.token, borrower, amount);

        emit Borrow(id, amount);

        _sortIntoQ(id);

        return true;
    }

    /**
     * @dev - Transfers tokens from a credit line ID to a Lender.
              Lender is only allowed to withdraw tokens not already lent out (prevents bank run)
              Accrued interest calculated (profit) and is withdrawn first then principal/deposit is reduced
     * @dev - callable by Lender on `id`
     * @param id -the credit line id from which the Lender is withdrawing
     * @param amount - amount of tokens the Lender would like to withdraw (withdrawn amount may be lower)
     */
    function withdraw(bytes32 id, uint256 amount)
        external
        override
        returns (bool)
    {
        Credit memory credit = credits[id];

        if(msg.sender != credit.lender) { revert CallerAccessDenied(); }

        // accrues interest and transfers to Lender
        credits[id] = CreditLib.withdraw(_accrue(credit, id), id, amount);

        LineLib.sendOutTokenOrETH(credit.token, credit.lender, amount);

        return true;
    }

    /**
     * @dev - Deletes a credit line id thus preventing any more borrowing.
     *      - Only callable by Borrower or Lender
     *      - Requires that the credit has already been repais in full
     * @dev - callable by `borrower`
     * @param id -the credit line id to be closed
     */
    function close(bytes32 id) external payable override returns (bool) {
        Credit memory credit = credits[id];
        address b = borrower; // gas savings
        if(msg.sender != credit.lender && msg.sender != b) {
          revert CallerAccessDenied();
        }

        // ensure all money owed is accounted for
        credit = _accrue(credit, id);
        uint256 facilityFee = credit.interestAccrued;
        if(facilityFee > 0) {
          // only allow repaying interest since they are skipping repayment queue.
          // If principal still owed, _close() MUST fail
          LineLib.receiveTokenOrETH(credit.token, b, facilityFee);

          credit = _repay(credit, id, facilityFee);
        }

        _close(credit, id); // deleted; no need to save to storage

        return true;
    }

    //////////////////////
    //  Internal  funcs //
    //////////////////////

    // updateStatus() will return a change in status (if it has changed). If the status has changed, it won't however return what ther prior status was.
    function _updateStatus(LineLib.STATUS status_) internal returns(LineLib.STATUS) {
      if(status == status_) return status_;
      emit UpdateStatus(uint256(status_));
      return (status = status_);
    }
    // creates the credit line in the system including the id
    function _createCredit(
        address lender,
        address token,
        uint256 amount
    )
        internal
        returns (bytes32 id)
    {
        id = CreditLib.computeId(address(this), lender, token);
        // MUST not double add the credit line. otherwise we can not _close()
        if(credits[id].lender != address(0)) { revert PositionExists(); }

        credits[id] = CreditLib.create(id, amount, lender, token, address(oracle));

        ids.push(id); // add lender to end of repayment queue
        
        unchecked { ++count; }

        return id;
    }

  /**
   * @dev - Reduces `principal` and/or `interestAccrued` on a credit line.
            Expects checks for conditions of repaying and param sanitizing before calling
            e.g. early repayment of principal, tokens have actually been paid by borrower, etc.
   * @param id - credit line id with all data pertaining to line
   * @param amount - amount of Credit Token being repaid on credit line
  */
    function _repay(Credit memory credit, bytes32 id, uint256 amount)
        internal
        returns (Credit memory)
    { 
        credit = CreditLib.repay(credit, id, amount);

        // if credit line fully repaid then remove it from the repayment queue
        if (credit.principal == 0) ids.stepQ();

        return credit;
    }

    /**
     * @notice - checks that a credit line is fully repaid and removes it
     * @dev deletes credit storage. Store any data u might need later in call before _close()
     */
    function _close(Credit memory credit, bytes32 id) internal virtual returns (bool) {
        if(credit.principal > 0) { revert CloseFailedWithPrincipal(); }

        // return the Lender's funds that are being repaid
        if (credit.deposit + credit.interestRepaid > 0) {
            LineLib.sendOutTokenOrETH(
                credit.token,
                credit.lender,
                credit.deposit + credit.interestRepaid
            );
        }

        delete credits[id]; // gas refunds

        // remove from active list
        ids.removePosition(id);
        unchecked { --count; }

        // If all credit lines are closed the the overall Line of Credit facility is declared 'repaid'.
        if (count == 0) { _updateStatus(LineLib.STATUS.REPAID); }

        emit CloseCreditPosition(id);

        return true;
    }

    /**
     * @notice - Insert `p` into the next availble FIFO position in the repayment queue
               - once earliest slot is found, swap places with `p` and position in slot.
     * @param p - position id that we are trying to find appropriate place for
     * @return
     */
    function _sortIntoQ(bytes32 p) internal returns (bool) {
        uint256 lastSpot = ids.length - 1;
        uint256 nextQSpot = lastSpot;
        bytes32 id;
        for (uint256 i; i <= lastSpot; ++i) {
            id = ids[i];
            if (p != id) {

              // Since we aren't constantly trimming array size to to remove empty elements
              // we should try moving elements to front of array in this func to reduce gas costs 
              // only practical if > 10 lenders though
              // just inc a vacantSlots and push each id to i - vacantSlot and count = len - vacantSlot

                if (
                  id == bytes32(0) ||       // deleted element
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

