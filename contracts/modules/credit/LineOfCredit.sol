import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LoanLib} from "../../utils/LoanLib.sol";
import {CreditLib} from "../../utils/CreditLib.sol";
import {CreditListLib} from "../../utils/CreditListLib.sol";
import {MutualConsent} from "../../utils/MutualConsent.sol";
import {InterestRateCredit} from "../interest-rate/InterestRateCredit.sol";

import {IOracle} from "../../interfaces/IOracle.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";

contract LineOfCredit is ILineOfCredit, MutualConsent {
    using SafeERC20 for IERC20;

    using CreditListLib for bytes32[];

    address public immutable borrower;

    address public immutable arbiter;

    IOracle public immutable oracle;

    InterestRateCredit public immutable interestRate;

    uint256 public immutable deadline;

    uint256 private count; // amount of open positions
    bytes32[] public ids; // all active positions

    mapping(bytes32 => Credit) public credits; // id -> Credit

    // Loan Financials aggregated accross all existing  Credit
    LoanLib.STATUS public loanStatus;

    uint256 public principalUsd; // initial principal
    uint256 public interestUsd; // unpaid interest

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

        LoanLib.updateStatus(loanStatus, LoanLib.STATUS.ACTIVE);

        emit DeployLoan(oracle_, arbiter_, borrower_);
    }

    function init() external virtual returns(LoanLib.STATUS) {
      return _init();
    }

    function _init() internal virtual returns(LoanLib.STATUS) {
       // If no modules then loan is immediately active
      return LoanLib.updateStatus(loanStatus, LoanLib.STATUS.ACTIVE);
    }

    ///////////////
    // MODIFIERS //
    ///////////////

    modifier whileActive() {
        if(loanStatus != LoanLib.STATUS.ACTIVE) { revert NotActive(); }
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

    function healthcheck() external returns (LoanLib.STATUS) {
        return LoanLib.updateStatus(loanStatus, _healthcheck());
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
        if (block.timestamp >= deadline && count > 0) {
            emit Default(ids[0]); // can query all defaulted positions offchain once event picked up
            return LoanLib.STATUS.LIQUIDATABLE;
        }

        return LoanLib.STATUS.ACTIVE;
    }

    /**
  * @notice - Returns total credit obligation of borrower.
              Aggregated across all lenders.
              Denominated in USD 1e8.
  * @dev    - callable by anyone
  */
    function getOutstandingDebt() external override returns (uint256) {
        (uint256 p, uint256 i) = _updateOutstandingDebt();
        return p + i;
    }

    function updateOutstandingDebt() external override returns (uint256, uint256) {
        return _updateOutstandingDebt();
    }

    function _updateOutstandingDebt()
        internal
        returns (uint256 principal, uint256 interest)
    {
        uint256 len = count;
        if (len == 0) return (0, 0);

        Credit memory credit;
        bytes32 id ;
        for (uint256 i = 0; i < len; i++) {
            id = ids[i];
            credit = CreditLib.accrue(credit, id, interestRate);

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

        principalUsd = principal;
        interestUsd = interest;
    }

    /**
     * @dev - Loops over all credit positions, calls InterestRate module with position data,
            then updates `interestAccrued` on position with returned data.
    */
    function accrueInterest() external override returns(bool) {
        uint256 len = count;
        bytes32 id;
        Credit memory credit;
        for (uint256 i = 0; i < len; i++) {
          id = ids[i];
          credits[id] = CreditLib.accrue(credits[id], id, interestRate);
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
        virtual
        override
        whileActive
        mutualConsent(lender, borrower)
        returns (bytes32)
    {
        IERC20(token).safeTransferFrom(lender, address(this), amount);

        bytes32 id = _createCredit(lender, token, amount, 0);

        require(interestRate.setRate(id, drate, frate));
        
        return id;
    }

    /**
    * @notice           - Let lender and borrower update rates on a aposition
    *                   - can set Rates even when LIQUIDATABLE for refinancing
    * @dev              - include lender in params for cheap gas and consistent API for mutualConsent
    * @dev              - callable by borrower or any lender
    * @param id - credit id that we are updating
    * @param lender     - lender on id
    * @param drate      - new drawn rate
    * @param frate      - new facility rate
    
    */
    function setRates(
        bytes32 id,
        address lender,
        uint128 drate,
        uint128 frate
    )
      external
      override
      mutualConsent(lender, borrower)
      returns (bool)
    {
        Credit memory credit = credits[id];
        credits[id] = CreditLib.accrue(credit, id, interestRate);
        require(interestRate.setRate(id, drate, frate));
        emit SetRates(id, drate, frate);
        return true;
    }


 /**
    * @notice           - Let lender and borrower increase total capacity of position
    *                   - can only increase while loan is healthy and ACTIVE.
    * @dev              - include lender in params for cheap gas and consistent API for mutualConsent
    * @dev              - callable by borrower    
    * @param id - credit id that we are updating
    * @param lender     - lender on id
    * @param amount     - amount to increase deposit / capaciity by
    * @param principal - amount to immediately draw down and send to borrower
    */
    function increaseCredit(
        bytes32 id,
        address lender,
        uint256 amount    )
      external
      override
      whileActive
      mutualConsent(lender, borrower)
      returns (bool)
    {
        Credit memory credit = credits[id];
        credit = CreditLib.accrue(credit, id, interestRate);
        
        credit.deposit += amount;

        credits[id] = credit;

        IERC20(credit.token).safeTransferFrom(credit.lender, address(this), amount);

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
        Credit memory credit = credits[id];
        credit = CreditLib.accrue(credit, id, interestRate);

        uint256 totalOwed = credit.principal + credit.interestAccrued;

        // clear the debt then close and delete position
        _close(_repay(credit, id, totalOwed), id);

        // borrower deposits remaining balance not already repaid and held in contract
        IERC20(credit.token).safeTransferFrom(msg.sender, address(this), totalOwed);
        
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
        Credit memory credit = credits[id];
        credit = CreditLib.accrue(credit, id, interestRate);

        require(amount <= credit.principal + credit.interestAccrued);

        credits[id] = _repay(credit, id, amount);

        IERC20(credit.token).safeTransferFrom(msg.sender, address(this), amount);

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
        Credit memory credit = credits[id];
        credit = CreditLib.accrue(credit, id, interestRate);

        if(amount > credit.deposit - credit.principal) { revert NoLiquidity(id) ; }

        credit.principal += amount;


        credits[id] = credit; // save new debt before healthcheck

        if(LoanLib.updateStatus(loanStatus, _healthcheck()) != LoanLib.STATUS.ACTIVE) { 
            revert NotActive();
        }

        credits[id] = credit;

        IERC20(credit.token).safeTransfer(borrower, amount);

        emit Borrow(id, amount);

        require(_sortIntoQ(id));

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

        if(msg.sender != credit.lender) {
          revert CallerAccessDenied();
        }

        credit = CreditLib.accrue(credit, id, interestRate);

        credits[id] = CreditLib.withdraw(credit, id, amount);

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
      Credit memory credit = credits[id];
      if(msg.sender != credit.lender && msg.sender != borrower) {
          revert CallerAccessDenied();
        }

        _close(credit, id);

        return true;
    }

    //////////////////////
    //  Internal  funcs //
    //////////////////////

    function _createCredit(
        address lender,
        address token,
        uint256 amount,
        uint256 principal
    ) internal returns (bytes32 id) {
        id = LoanLib.computePositionId(address(this), lender, token);

        // MUST not double add position. otherwise we can not _close()
        if(credits[id].lender != address(0)) { revert PositionExists(); }

        (bool passed, bytes memory result) = token.call(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimals = !passed ? 18 : abi.decode(result, (uint8));
        
        int price = IOracle(oracle).getLatestAnswer(token);
        if(price <= 0 ) { revert NoTokenPrice(); }

        credits[id] = Credit({
            lender: lender,
            token: token,
            decimals: decimals,
            deposit: amount,
            principal: principal,
            interestAccrued: 0,
            interestRepaid: 0
        });

        ids.push(id); // add lender to end of repayment queue
        ++count;

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
    function _repay(Credit memory credit, bytes32 id, uint256 amount)
        internal
        returns (Credit memory)
    { 
        credit = CreditLib.repay(credit, id, amount);

        // if credit fully repaid then remove lender from repayment queue
        if (credit.principal == 0) ids.stepQ();

        return credit;
    }


    /**
     * @notice - checks that credit is fully repaid and remvoes from available lines of credit.
     * @dev deletes Credit storage. Store any data u might need later in call before _close()
     */
    function _close(Credit memory credit, bytes32 id) internal virtual returns (bool) {
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
        ids.removePosition(id);
        --count;

        // brick loan contract if all positions closed
        if (count == 0) { LoanLib.updateStatus(loanStatus, LoanLib.STATUS.REPAID); }

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
        uint256 len = count;
        uint256 _i = 0; // index that p should be moved to

        for (uint256 i = 0; i < len; i++) {
            bytes32 id = ids[i];
            if (p != id) {
                if (id == bytes32(0) || credits[id].principal > 0) continue; // `id` should be placed before `p`

                _i = i; // index of first undrawn LoC found
            } else {
                if (_i == 0) return true; // `p` in earliest possible index
                // swap positions
                ids[i] = ids[_i];
                ids[_i] = p;
            }
        }

        return true;
    }
}
