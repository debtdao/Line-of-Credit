pragma solidity ^0.8.9;

// Helpers
import { MutualUpgrade } from "../../utils/MutualUpgrade.sol";
import { LoanLib } from "../../utils/LoanLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// module interfaces 
import { ILoan } from "../../interfaces/ILoan.sol";
import { IEscrow } from "../../interfaces/IEscrow.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IInterestRate } from "../../interfaces/IInterestRate.sol";
import { IModule } from "../../interfaces/IModule.sol";

abstract contract BaseLoan is ILoan, MutualUpgrade {  
  address immutable borrower;   // borrower being lent to

  mapping(bytes32 => DebtPosition) public debts; // positionId -> DebtPosition
  bytes32[] positionIds; // all active positions

  // Loan Financials aggregated accross all existing  DebtPositions
  LoanLib.STATUS public loanStatus;

  // all deonminated in USD
  uint256 public principal; // initial loan  drawdown
  uint256 public totalInterestAccrued;// unpaid interest

  // i dont think we need to keep global var on this. only check per debt position
  uint256 public maxDebtValue; // total amount of USD value to be pulled from loan

  // Loan Modules
  address public oracle;  // could move to LoanLib and make singleton
  address public arbiter; // could make dynamic/harcoded ens('arbiter.debtdao.eth')
  address public escrow;
  address public interestRateModel;

  // ordered by most likely to return early in healthcheck() with non-ACTIVE status
  address[3] public modules = [escrow, oracle, interestRateModel];

  /**
   * @dev - Loan borrower and proposed lender agree on terms
            and add it to potential options for borrower to drawdown on
            Lender and borrower must both call function for MutualUpgrade to add debt position to Loan
   * @param maxDebtValue_ - total debt accross all lenders that borrower is allowed to create
   * @param oracle_ - price oracle to use for getting all token values
   * @param arbiter_ - neutral party with some special priviliges on behalf of borrower and lender
   * @param borrower_ - the debitor for all debt positions in this contract
   * @param escrow_ - contract holding all collateral for borrower
   * @param interestRateModel_ - contract calculating lender interest from debt position values
  */
  constructor(
    uint256 maxDebtValue_,
    address oracle_,
    address arbiter_,
    address borrower_,
    address escrow_,
    address interestRateModel_
  ) {
    maxDebtValue = maxDebtValue_;

    borrower = borrower_;
    interestRateModel = interestRateModel_;
    escrow = escrow_;
    arbiter = arbiter_;
    oracle = oracle_;

    loanStatus = LoanLib.STATUS.INITIALIZED;
  }

  ///////////////
  // MODIFIERS //
  ///////////////

  // TODO better naming for this function
  modifier isOperational(LoanLib.STATUS status) {
    require(
      status >= LoanLib.STATUS.ACTIVE && 
      status <= LoanLib.STATUS.DELINQUENT,
      'Loan: no op'
    );
    _;
  }

  modifier onlyBorrower() {
    require(msg.sender == borrower, 'Loan: only borrower');
    _;
  }

  modifier onlyArbiter() {
    require(msg.sender == arbiter, 'Loan: only arbiter');
    _;
  }

  modifier validPositionId(bytes32 positionId) {
    require(debts[positionId].lender != address(0), "Loan: invalid position ID");
    _;
  }
  ///////////
  // HOOKS //
  ///////////

    /**
   * @dev  Used to addc custom liquidation functionality until we create separate Liquidation module
   * @param debt - debt position data for loan being repaid
   * @return usd value of assets liquidated
  */
  function _liquidate(DebtPosition memory debt) virtual internal returns(uint256) {
    require(loanStatus == LoanLib.STATUS.LIQUIDATABLE, "Loan: not liquidatable");
    return 0;
  }

  /**
   * @dev  Called in _repay() to get amount of debt that borrower is currently allowed to repay
   * @param debt - debt position data for loan being repaid
   * @param requestedRepayAmount - amount of debt that the borrower would like to pay
   * @return - amount borrower is allowedto repay. Returns 0 if repayment is not allowed
  */
  function _getMaxRepayableAmount(DebtPosition memory debt, uint256 requestedRepayAmount) virtual internal returns(uint256) {}


  /**
   * @dev  Calls interestRate contract and gets amount of interest owned on debt position
   * @param debt - debt position data for loan being calculated
   * @return total interest to add to position
  */
  function _getInterestPaymentAmount(DebtPosition memory debt) virtual internal returns(uint256) {}

  /**
   * @dev  2/2 multisig between borrower and arbiter (on behalf of al llenders) to agree on T&C of loan
        Once agreed by both parties sets loanStatus to ACTIVE allowing borrwoing and interest accrual
  */
  function _init() virtual internal returns(bool) {
    _updateLoanStatus(LoanLib.STATUS.ACTIVE);
    return true;
  }

  /**
   *  @dev - loops through all modules and returns their status if required last to savegas on override external calls
   *        returns early if returns non-ACTIVE
  */
  function _healthcheck() virtual internal returns(LoanLib.STATUS status) {
    if(principal + totalInterestAccrued > maxDebtValue)
      return _updateLoanStatus(LoanLib.STATUS.OVERDRAWN);
      
    for(uint i; i < modules.length; i++) {
       // should we differentiate failed calls vs bad statuses?
      status = IModule(modules[i]).healthcheck();
      if(status != LoanLib.STATUS.ACTIVE)
        return _updateLoanStatus(status);
    }
    
    return loanStatus;
  }
  
  /**
  @dev Returns total debt obligation of borrower.
       Aggregated across all lenders.
       Denominated in USD.
  */
  function getOutstandingDebt() override external returns(uint256) {
    return principal + totalInterestAccrued;
  }

  /**
   * @dev - Loan borrower and proposed lender agree on terms
            and add it to potential options for borrower to drawdown on
            Lender and borrower must both call function for MutualUpgrade to add debt position to Loan
   * @param amount - amount of `token` to initially deposit
   * @param token - the token to be lent out
   * @param lender - address that will manage debt position 
  */
  function addDebtPosition(
    uint256 amount,
    address token,
    address lender
  )
    mutualUpgrade(lender, borrower) 
    override external
    returns(bool)
  {
    bytes32 positionId = LoanLib.computePositionId(address(this), lender, token);
    
    // MUST not double add position. otherwise we can not _close()
    require(debts[positionId].lender == address(0), 'Loan: position exists');

    bool success = IERC20(token).transferFrom(
      lender,
      address(this),
      amount
    );
    require(success, 'Loan: no tokens to lend');

    debts[positionId] = DebtPosition({
      lender: lender,
      token: token,
      principal: 0,
      interestAccrued: 0,
      deposit: amount
    });

    emit AddDebtPosition(lender, token, amount);

    // also add interest rate model here?
    return true;
  }
  
  /**
    @notice see _accrueInterest()
  */
  function accrueInterest() override external returns(uint256) {
    return _accrueInterest();
  }



  // Liquidation

  function liquidate(
    bytes32 positionId,
    uint256 amount,
    address escrowToken
  )
    onlyArbiter
    validPositionId(positionId)
    external
  {
    require(loanStatus == LoanLib.STATUS.LIQUIDATABLE, "Loan: not liquidatable");

    // call method within escrow contract
    // releasing everything to debt DAO multisig to be dealt with OTC
    IEscrow(escrow).liquidate(amount, escrowToken, arbiter);

    emit Liquidated(positionId, amount, escrowToken);
  }


  ///////////////
  // REPAYMENT //
  ///////////////

  /**
   * @dev - Transfers token used in debt position from msg.sender to Loan contract.
   * @notice - see _repay() for more details
   * @param positionId -the debt position to pay down debt on
   * @param amount - amount of `token` in `positionId` to pay back
  */

  function depositAndRepay(
    bytes32 positionId,
    uint256 amount
  )
    validPositionId(positionId)
    override external
    returns(bool)
  {
    _accrueInterest();
    DebtPosition memory debt = debts[positionId];

    // TODO check if early repayment is allowed on loan
    uint256 amountToRepay = debt.interestAccrued < amount ? debt.interestAccrued : amount;

    bool success = IERC20(debt.token).transferFrom(
      msg.sender,
      debt.lender,
      amountToRepay
    );
    require(success, 'Loan: failed repayment');

    _repay(debt, amountToRepay);
    return true;
  }

   /**
   * @dev - Transfers enough tokens to repay entire debt position from `borrower` to Loan contract.
            Only callable by borrower bc it closes position.
   * @param positionId -the debt position to pay down debt on and close
  */
  function depositAndClose(bytes32 positionId)
    onlyBorrower
    validPositionId(positionId)
    override external
    returns(bool)
  {
    _accrueInterest();
    DebtPosition memory debt = debts[positionId];

    uint256 totalOwed = debt.principal + debt.interestAccrued;

    // borrwer deposits remaining balance not already repaid and held in contract
    bool success = IERC20(debt.token).transferFrom(
      msg.sender,
      address(this),
      totalOwed
    );
    require(success, 'Loan: deposit failed');

    require(_repay(debt, totalOwed));
    require(_close(debt, positionId));
    return true;
  }
  
  ////////////////////
  // FUND TRANSFERS //
  ////////////////////
     /**
   * @dev - Transfers tokens from Loan to lender.
   *        Only allowed to withdraw tokens not already lent out (prevents bank run)
   * @param positionId -the debt position to pay down debt on and close
   * @param amount - amount of tokens lnder would like to withdraw (withdrawn amount may be lower)
  */
  function borrow(bytes32 positionId, uint256 amount)
    onlyBorrower
    validPositionId(positionId)
    override external
    returns(bool)
  {
    _accrueInterest();
    DebtPosition memory debt = debts[positionId];
    
    require(amount <= debt.deposit - debt.principal, 'Loan: no liquidity');

    debt.principal += amount;
    principal += _getUsdValue(debt.token, amount);
    // TODO call escrow contract and see if loan is still healthy before sending funds

    bool success = IERC20(debt.token).transferFrom(
      address(this),
      borrower,
      amount
    );
    require(success, 'Loan: borrow failed');


    emit Borrow(debt.lender, debt.token, amount);

    return true;
  }

   /**
   * @dev - Transfers tokens from Loan to lender.
   *        Only allowed to withdraw tokens not already lent out (prevents bank run)
   * @param positionId -the debt position to pay down debt on and close
   * @param amount - amount of tokens lnder would like to withdraw (withdrawn amount may be lower)
  */
  function withdraw(bytes32 positionId, uint256 amount) override external returns(bool) {
    require(msg.sender == debts[positionId].lender);
    
    _accrueInterest();
    DebtPosition memory debt = debts[positionId];
    
    require(amount <  debt.deposit - debt.principal, 'Loan: no liquidity');

    debt.deposit -= amount;
    bool success = IERC20(debt.token).transferFrom(
      address(this),
      debt.lender,
      amount
    );
    require(success, 'Loan: withdraw failed');


    emit Withdraw(debt.lender, debt.token, amount);

    return true;
  }


  /**
   * @dev - Deletes debt position preventing any more borrowing.
   *        Only callable by borrower or lender for debt position
   * @param positionId -the debt position to close
  */
  function close(bytes32 positionId) override external returns(bool) {
    DebtPosition memory debt = debts[positionId];
    require(
      msg.sender == debt.lender ||
      msg.sender == borrower
    );
    require(debt.principal + debt.interestAccrued == 0, 'Loan: close failed. debt owed');
    
    // repay lender initial deposit + accrued interest
    if(debt.deposit > 0) {
      require(IERC20(debt.token).transfer(debt.lender, debt.deposit));
    }

    require(_close(debt, positionId));
    
    return true;
  }


  /**
   * @dev - Allows lender to pull all funds from contract, realizing any losses from non-payment.
   * @param positionId -the debt position to close
  */
  function emergencyClose(bytes32 positionId) override external returns(bool) {
    DebtPosition memory debt = debts[positionId];
    require(msg.sender == debt.lender);

    if(debt.deposit > 0) {
      uint256 availableFunds = IERC20(debt.token).balanceOf(address(this));
      uint256 recoverableFunds = availableFunds > debt.deposit ? debt.deposit : availableFunds;
      require(IERC20(debt.token).transfer(debt.lender, recoverableFunds));
    }

    require(_close(debt, positionId));
    
    return true;
  }

  // prviliged interal functions
  /**
   * @dev - Reduces `principal` and/or `interestAccrued` on debt position, increases lender's `deposit`.
            Reduces global USD principal and totalInterestAccrued values.
            Expects checks for conditions of repaying and param sanitizing before calling
            e.g. early repayment of principal, tokens have actually been paid by borrower, etc.
   * @param debt - debt position struct with all data pertaining to loan
   * @param amount - amount of token being repaid on debt position
  */
  function _repay(
    DebtPosition memory debt,
    uint256 amount
  )
    isOperational(loanStatus)
    internal
    returns(bool)
  {
    // should we refresh all values in usd here?
    if(amount < debt.interestAccrued) {
      debt.interestAccrued -= amount;
      totalInterestAccrued -= _getUsdValue(debt.token, amount);
    } else {
      uint256 price = _getTokenPrice(debt.token);
      
      // update global debt denominated in usd
      principal -= price * (amount - debt.interestAccrued);
      totalInterestAccrued -= price * debt.interestAccrued;

      // update individual debt position denominated in token
      debt.principal -= debt.interestAccrued;
      // TODO update debt.deposit here or _accureInterest()?
      debt.interestAccrued = 0;
    }

    emit Repay(debt.lender, debt.token, amount);

    return true;
  }

  /**
   * @dev - Loops over all debt positions, calls InterestRate module with position data,
            then updates `interestAccrued` on position with returned data.
            Also updates global USD values for `totalInterestAccrued`.
            Can only be called when loan is not in distress
  */
  function _accrueInterest() internal isOperational(loanStatus) returns (uint256 accruedAmount) {
    uint256 len = positionIds.length;
    DebtPosition memory debt;

    for(uint256 i = 0; i < len; i++) {
      debt = debts[positionIds[len]];
      // get token demoninated interest accrued
      uint256 tokenIncrease = IInterestRate(interestRateModel).accrueInterest(
        len, // IR settings break if positionID changes. need constant/deterministic id
        debt.principal,
        loanStatus
      );

      // update debts balance
      debt.interestAccrued += tokenIncrease;
      // should we be increaseing deposit here or in _repay()?
      debt.deposit += tokenIncrease;

      // get USD value of interest accrued
      accruedAmount += _getUsdValue(debt.token, tokenIncrease);
    }

    totalInterestAccrued += accruedAmount;
  }

  function _close(DebtPosition memory debt, bytes32 positionId) internal returns(bool) {
    // delete position and remove from active list
    delete debts[positionId]; // yay gas refunds!!!
    positionIds = LoanLib.removePosition(positionIds, positionId);

    // brick loan contract if all positions closed
    if(positionIds.length == 0) {
      loanStatus = LoanLib.STATUS.REPAID;
    }

    emit CloseDebtPosition(debt.lender, debt.token);

    return true;
  }

  // Helper functions
  function _updateLoanStatus(LoanLib.STATUS status) internal returns(LoanLib.STATUS) {
    loanStatus = status;
    emit UpdateLoanStatus(uint256(status));
    return status;
  }

  /**
   * @dev - Calls Oracle module to get most recent price for token.
            All prices denominated in USD.
   * @param token - token to get price for
  */
  function _getTokenPrice(address token) internal returns (uint256) {
    return IOracle(oracle).getLatestAnswer(token);
  }

    /**
   * @dev - Calls Oracle module to get most recent price for token.
            All prices denominated in USD.
   * @param token - token to get price for
   * @param amount - amount of tokens to get total usd value for
  */
  function _getUsdValue(address token, uint256 amount) internal returns (uint256) {
    return _getTokenPrice(token) * amount;
  }

}
