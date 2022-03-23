pragma solidity ^0.8.9;

// Helpers
import { MutualUpgrade } from "./MutualUpgrade.sol";
import { LoanLib } from "./lib/LoanLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// module interfaces 
import { IEscrow } from "./interfaces/IEscrow.sol";
import { IOracle } from "./interfaces/IOracle.sol";
import { IInterestRate } from "./interfaces/IInterestRate.sol";
import { IModule } from "./interfaces/IModule.sol";
import { ISpigotConsumer } from "./interfaces/ISpigotConsumer.sol";

contract Loan is IModule, MutualUpgrade {  

  // Stakeholder data
  struct DebtPosition {
    address lender;           // person to repay
    address token;            // token being lent out
    // all deonminated in token, not USD
    uint256 deposit;          // total liquidity provided by lender for token
    uint256 principal;        // amount actively lent out
    uint256 interestAccrued;  // interest accrued but not repaid
  }

  // Loan events


  // DebtPosition events
  event Withdraw(address indexed lender, address indexed token, uint256 indexed amount);

  event AddDebtPosition(address indexed lender, address indexed token, uint256 indexed deposit);

  event CloseDebtPosition(address indexed lender, address indexed token);


  // Loan Events
  event Borrow(address indexed lender, address indexed token, uint256 indexed amount);

  event Repay(address indexed lender, address indexed token, uint256 indexed amount);

  
  // General Events
  
  event UpdateLoanStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph


  address immutable borrower;   // borrower being lent to
  
  // could make NFT ids to make it easier to transfer after the fact
  // is it an issue that positionId is not static from UX perspective?
  // harder to do things programmatically and create singleton contracts
  // e.g. all DEBT staking could be in one contract and reference positionId so ur backing specific lender on specific loan even.
  uint256 public positionIds; // incremental ids of DebtPositions. 0 indexed
  
  mapping(uint => DebtPosition) public debts; // positionId -> DebtPosition


  // vars still missing
  // start time
  // term length
  // ability to repay interest or principal too
  // compounding rate

  // Loan Financials aggregated accross all existing  DebtPositions
  LoanLib.STATUS public loanStatus;
  // all deonminated in USD
  uint256 public principal; // initial loan  drawdown
  uint256 public totalInterestAccrued;// principal + interest

  // i dont think we need to keep global var on this. only check per debt position
  uint256 public maxDebtValue; // total amount of USD value to be pulled from loan

  // Loan Modules
  address public spigot;
  address public oracle;  // could move to LoanLib and make singleton
  address public arbiter; // could make dynamic/harcoded ens('arbiter.debtdao.eth')
  address public escrow;
  address public interestRateModel;

  // ordered by most likely to return early in healthcheck() with non-ACTIVE status
  IModule[4] public modules = [escrow, spigot, oracle, interestRateModel];

  constructor(
    uint256 maxDebtValue_,
    address oracle_,
    address spigot_,
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
    spigot = spigot_;

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

  modifier onlyBorrower(address addr) {
    require(addr == borrower, 'Loan: only borrower');
    _;
  }

  ////////////////
  // MODULE INTERFACE //
  ////////////////

  function loan() external returns(address) {
    return address(this);
  }

  /**
  @dev  2/2 multisig between borrower and arbiter (on behalf of al llenders) to agree on T&C of loan
        Once agreed by both parties sets loanStatus to ACTIVE allowing borrwoing and interest accrual
  */
  function init()
    mutualUpgrade(arbiter, borrower) // arbiter atm for efficiency so no parsing lender array
    external
  {
    // I lean towards option 1 vs option 2
    // on second thought i like option 2 because init can happen whenever, we only care that it happened
    // e.g. someone besides borrower puts up the collateral
    // require(IEscrow(escrow).init(borrower)); // transfer all required collateral before activating loan
    // require(
    //   module.loan() == this &&
    //   module.healthcheck() == LoanLib.STATUS.ACTIVE,
    //   'Loan: no collateral to init'
    // );
    
    for(uint i; i < modules.length; i++) {
      require(modules[i].init(), 'Loan: misconfigured module');
    }

    // probably also need to check that the modules have this Loan contract

    // check spigot has control of revenue contracts here?
    // transfer DEBT as origination fee?

    // or can make initialized and have separate function for executing everything after agreed updon in mutualUpgrade.
    // just annoying if one module doesnt work, both parties have to keep calling init() to ACTIVE loan instead of 
    _updateLoanStatus(LoanLib.STATUS.ACTIVE);
  }

  /**
   *  @dev - loops through all modules and returns their status if required last to savegas on external calls
   *        returns early if returns non-ACTIVE
  */
  function healthcheck() external returns(LoanLib.STATUS status) {
    if(principal + totalInterestAccrued > maxDebtValue)
      return _updateLoanStatus(LoanLib.STATUS.OVERDRAWN);
      
    for(uint i; i < modules.length; i++) {
      status = modules[i].healthcheck();
      if(status != LoanLib.STATUS.ACTIVE)
        return _updateLoanStatus(status);
    }
    
    return loanStatus;
  }

  //
  // Inititialiation
  //

  
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
    external
  {
    bool success = IERC20(token).transferFrom(
      lender,
      address(this),
      amount
    );
    require(success, 'Loan: no tokens to lend');

    positionIds += 1;
    dbets[positionIds] = DebtPosition({
      lender: lender,
      token: token,
      principal: 0,
      interestAccrued: 0,
      deposit: amount
    });

    emit AddDebtPosition(lender, token, amount);

    // also add interest rate model here?
  }


  //////////////////
  // MAINTAINENCE //
  //////////////////


  /**
    @notice see _accrueInterst()
  */
  function accrueInterest() external returns(uint256) {
    return _accrueInterest();
  }


  
  ///////////////
  // REPAYMENT //
  ///////////////

  /**
   * @dev - Transfers token used in debt position from msg.sender to Loan contract.
   * @notice - see repay() for more details
   * @param positionId -the debt position to pay down debt on
   * @param amount - amount of `token` in `positionId` to pay back
  */

  function depositAndRepay(
    uint256 positionId,
    uint256 amount
  )
    external
  {
    require(positionId <= positionIds);
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
  }


 /**
   * @dev - 
            Only callable by borrower for security pasing arbitrary data in contract call
            and they are most incentivized to get best price on assets being sold.
   * @notice see _repay() for more details
   * @param positionId -the debt position to pay down debt on
   * @param claimToken - The revenue token escrowed by Spigot to claim and use to repay debt
   * @param zeroExTradeData - data generated by 0x API to trade `claimToken` against their exchange contract
  */
  function claimSpigotAndRepay(
    uint256 positionId,
    address claimToken,
    bytes[] calldata zeroExTradeData
  )
    onlyBorrower(msg.sender)
    external
  {
    require(positionId <= positionIds);

    _accrueInterest();
    DebtPosition memory debt = debts[positionId];

    // need to check with 0x api on where bought tokens go to by default
    // see if we can change that to Loan instead of SpigotConsumer
    uint256 tokensBought = ISpigotConsumer(spigot).claimAndTrade(
      claimToken,
      debt.token,
      zeroExTradeData
    );

    // TODO check if early repayment is allowed on loan
    // then update logic here. Probs need an internal func
    uint256 amountToRepay = debt.interestAccrued < tokensBought ?
      debt.interestAccrued :
      tokensBought;

    // claim bought tokens from spigot to repay loan
    require(
      ISpigotConsumer(spigot).stream(address(this), debt.token, amountToRepay),
      'Loan: failed repayment'
    );

    _repay(debt, amountToRepay);
  }

   /**
   * @dev - Transfers enough tokens to repay entire debt position from `borrower` to Loan contract.
            Only callable by borrower bc it closes position.
   * @param positionId -the debt position to pay down debt on and close
  */
  function depositAndClose(uint256 positionId) onlyBorrower(msg.sender) external {
    require(positionId <= positionIds);

    _accrueInterest();
    DebtPosition memory debt = debts[positionId];

    // TODO check early repayment logic
    uint256 totalOwed = debt.principal + debt.interestAccrued;
    IERC20 token = IERC20(debt.token);

    // borrwer deposits remaining balance not already repaid and held in contract
    bool success = token.transferFrom(
      msg.sender,
      address(this),
      totalOwed
    );
    require(success, 'Loan: deposit failed');

    require(_repay(debt, totalOwed));
    require(_close(debt));
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
  function borrow(uint256 positionId, uint256 amount)
    onlyBorrower(msg.sender)
    external returns(bool)
  {
    require(positionId <= positionIds);  
    _accrueInterest();
    DebtPosition memory debt = debts[positionId];
    
    require(amount <= debt.deposit - debt.principal, 'Loan: no liquidity');

    debt.principal += amount;
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
  function withdraw(uint256 positionId, uint256 amount) external returns(bool) {
    require(msg.sender == debts[positionId].lender);
    
    _accrueInterest();
    DebtPosition memory debt = debts[positionId];
    
    uint256 availableToWithdraw = debt.deposit - debt.principal;
    require(availableToWithdraw > 0, 'Loan: no liquidity');

    uint256 amountToWithdraw = amount < availableToWithdraw ? amount : availableToWithdraw;
    
    debt.deposit -= amountToWithdraw;
    bool success = IERC20(debt.token).transferFrom(
      address(this),
      debt.lender,
      amountToWithdraw
    );
    require(success, 'Loan: deposit failed');


    emit Withdraw(debt.lender, debt.token, amountToWithdraw);

    return true;
  }


  /**
   * @dev - Deletes debt position preventing any more borrowing.
   *        Only callable by borrower or lender for debt position
   * @param positionId -the debt position to close
  */
  function close(uint256 positionId) external {
    require(
      msg.sender == debts[positionId].lender ||
      msg.sender == borrower
    );
    require(_close(debts[positionId]));
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
    uint256 len = positionIds;
    DebtPosition memory debt;
    uint256 accruedAmount = 0;

    for(uint256 i = 0; i <= len; i++) {
      debt = debts[len];
      // get token demoninated interest accrued
      uint256 tokenIncrease = IInterestRate(interestRateModel).accrueInterest(
        len, // IR settings break if positionID changes. need constant/deterministic id
        debt.principal,
        debt.deposit,
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
    return accruedAmount;
  }

  function _close(DebtPosition memory debt) internal returns(bool) {
    // potential attacck vector, currently only lender can reduce deposit.
    // If lender gets interest on deposit, not just principal, borrower can be forced
    // to pay interest even if they repaid debt and want to close
    require(debt.deposit == 0, 'Loan: close failed. debt owed');

    if(positionId != positionIds) {
      // replace closed debt position with last debt position
      debts[positionId] = debts[positionIds]; 
    }

    // delete final debt and decrement total debts
    delete debts[positionIds]; // yay gas refunds!!!
    positionIds--;

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
  function _getTokenPrice(address token) internal view returns (uint256) {
    return IOracle(oracle).getLatestAnswer(token);
  }

    /**
   * @dev - Calls Oracle module to get most recent price for token.
            All prices denominated in USD.
   * @param token - token to get price for
   * @param amount - amount of tokens to get total usd value for
  */
  function _getUsdValue(address token, uint256 amount) internal view returns (uint256) {
    return _getTokenPrice(token) * amount;
  }

}
