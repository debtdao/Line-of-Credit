pragma solidity ^0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MutualUpgrade } from "./MutualUpgrade.sol";
import { LoanLib } from "./lib/LoanLib.sol";
import { IEscrow } from "./interfaces/IEscrow.sol";
import { IOracle } from "./interfaces/IOracle.sol";
import { IInterestRate } from "./interfaces/IInterestRate.sol";
import { IModule } from "./interfaces/IModule.sol";
import { ISpigotConsumer } from "./interfaces/ISpigotConsumer.sol";

contract Loan is IModule, MutualUpgrade {
  // Stakeholder data
  struct DebtPosition {
    address lender;
    address token;
    uint256 principal;
    uint256 interestAccrued;
    uint256 maxDebtValue;
  }

  event UpdateLoanStatus(uint256 indexed status); // store as normal uint so it can be indexed in subgraph
  event Liquidated(uint256 positionId, uint256 amount, address token);

  address immutable borrower;   // borrower being lent to
  
  // could make NFT ids to make it easier to transfer after the fact
  uint256 immutable positionIds; // incremental ids of DebtPositions. 0 indexed
  
  mapping(uint => DebtPosition) public debts; // positionId -> DebtPosition


  // vars still missing
  // term length
  // ability to repay interest or principle too
  // 

  // Loan Financials aggregated accross all existing  DebtPositions
  LoanLib.STATUS public loanStatus;
  uint256 public principal; // initial loan  drawdown
  uint256 public totalInterestAccrued;// principal + interest
  uint256 public maxDebtValue; // total amount of USD value to be pulled from loan

  // Loan Modules
  address public spigot;
  address public oracle;  // could move to LoanLib and make singleton
  address public arbiter; // could make dynamic/harcoded ens('arbiter.debtdao.eth')
  address public escrow;
  address public interestRateModel;
  IModule[4] public modules = [spigot, oracle, escrow, interestRateModel];

  constructor(
    uint256 maxDebtValue_,
    address oracle_,
    address spigot_,
    address arbiter_,
    address borrower_,
    address escrow_,
    address interestRateModel_,
    DebtPosition[] memory debts_
  ) {
    maxDebtValue = maxDebtValue_;

    borrower = borrower_;
    interestRateModel = interestRateModel_;
    escrow = escrow_;
    arbiter = arbiter_;
    oracle = oracle_;
    spigot = spigot_;


    uint256 len = debts_.length - 1;
    positionIds = len; // set total amount of ids.

    unchecked {
      for(;;len--) {
        debts[len] = debts_[len];
      }
    }

    loanStatus = LoanLib.STATUS.UNINITIALIZED;
  }

  ///////////////
  // MODIFIERS //
  ///////////////

  // TODO better naming for this function
  modifier isOperational(LoanLib.STATUS status) {
    require(status >= LoanLib.STATUS.ACTIVE && status <= LoanLib.STATUS.DELINQUENT, 'Loan: invalid status');
    _;
  }

  modifier onlyBorrower(address addr) {
    require(addr == borrower, 'Loan: only borrower');
    _;
  }

  modifier onlyArbiter(address addr) {
    require(addr == arbiter, 'Loan: only arbiter');
    _;
  }

  modifier validPositionId(uint256 positionId) {
    require(positionId <= positionIds, "Loan: invalid position ID");
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
    //   IEscrow(escrow).healthcheck() == LoanLib.STATUS.ACTIVE,
    //   'Loan: no collateral to init'
    // );
    
    for(uint i; i < modules.length; i++) {
      require(
        address(this) == modules[i].loan() &&
        modules[i].healthcheck() == LoanLib.STATUS.ACTIVE,
        'Loan: misconfigured module'
      );
    }

    // probably also need to check that the modules have this Loan contract

    // check spigot has control of revenue contracts here?
    // transfer DEBT as origination fee?

    // or can make initialized and have separate function for executing everything after agreed updon in mutualUpgrade.
    // just annoying if one module doesnt work, both parties have to keep calling init() to ACTIVE loan instead of 
    _updateLoanStatus(LoanLib.STATUS.ACTIVE);
  }

  /**
    @dev loops through all modules and returns their status if required last to save gas on external calls
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


  //////////////////
  // MAINTENANCE //
  //////////////////


  /**
    @dev
  */
  function accrueInterest()
    isOperational(loanStatus)
    external
  {
    uint len = positionIds;
    DebtPosition memory debt;
    uint newTotal = totalInterestAccrued;

    for(uint i = 0; i < len; i++) {
      debt = debts[len];
      // get token demoninated interest accrued
      uint tokenIncrease = IInterestRate(interestRateModel).accrueInterest(
        i,
        debt.principal,
        loanStatus
      );

      // update debts balance
      debt.interestAccrued += tokenIncrease;
      // get USD value of interest accrued
      newTotal += _getUsdValue(debt.token, tokenIncrease);
    }

    totalInterestAccrued = newTotal;
  }


  // Liquidation

  function liquidate( // should this only be able to be called by the arbiter?
        uint256 positionId,
        uint256 amount
    )
        external onlyArbiter validPositionId(positionId)
    {
        // check to see if loan can be liquidated
        require(loanStatus = LoanLib.STATUS.LIQUIDATABLE, "Loan cannot be liquidated at this time");

        // pull loan 
        DebtPosition memory debt = debts[positionId];

        // call method within escrow contract
        escrowContract = IEscrow(escrow);
        escrowContract.releaseCollateral(debt.token, amount, arbiter); // releasing everything to debt DAO multisig to be dealt with OTC

        // emit liquidated event
        emit Liquidated(positionId, amount, debt.token);
    }

  // Repayment

  function depositAndRepay(
    uint256 positionId,
    uint256 amount
  )
    external validPositionId(positionId)
  {
    
    DebtPosition memory debt = debts[positionId];

    // TODO check if early repayment is allowed on loan
    uint256 amountToRepay = debt.interestAccrued < amount ? debt.interestAccrued : amount;
    // move to _repay()
    bool success = IERC20(debt.token).transferFrom(
      msg.sender,
      debt.lender,
      amountToRepay
    );
    require(success, 'Loan: failed repayment');

    _repay(debt, amountToRepay);
  }

  function claimSpigotAndRepay(
    uint256 positionId,
    address claimToken,
    bytes[] calldata zeroExTradeData
  )
    onlyBorrower(msg.sender) 
    validPositionId(positionId)
    external  
  {
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

    // tell spigot to send bought tokens to lender
    require(
      ISpigotConsumer(spigot).stream(debt.lender, debt.token, amountToRepay),
      'Loan: failed repayment'
    );

    _repay(debt, amountToRepay);
  }

  // privileged interal function
  // expects checks for conditions of repaying and param sanitizing before calling
  // e.g.  early repayment of principal, amount of tokens have actually been paid by borrower, etc.
  function _repay(
    DebtPosition memory debt,
    uint256 amount
  )
    isOperational(loanStatus)
    internal
    returns(bool)
  {

    if(amount < debt.interestAccrued) {
      uint256 interestPayment = _getUsdValue(debt.token, amount);
      debt.interestAccrued -= interestPayment;
      totalInterestAccrued -= interestPayment;
    } else {
      uint256 principalPayment = _getUsdValue(debt.token, amount - debt.interestAccrued);
      
      // update global debt
      principal -= principalPayment;
      totalInterestAccrued -= debt.interestAccrued;

      // update individual debt position
      debt.principal -= principalPayment;
      debt.interestAccrued = 0;
    }

    return true;
  }

  //
  function close(uint256 positionId) external {
       // if lender is fully paid out then replace their 
    // probably dont want this for line of credits
    require(debts[positionId].principal == 0);
    // move to _removeDebtPosition(positionId)

    if(positionId != positionIds) {
      // replace closed debt with last debt 
      debts[positionId] = debts[positionIds]; 
    }
    // delete final debt and decrement total debts
    delete debts[positionIds]; // yay gas refunds!!!
    positionIds--;
  }
  
  // Helper functions
  function _updateLoanStatus(LoanLib.STATUS status) internal returns(LoanLib.STATUS) {
    loanStatus = status;
    emit UpdateLoanStatus(uint256(status));
    return status;
  }

  function _getUsdValue(address token, uint256 amount) internal view returns (uint256) {
    return IOracle(oracle).getLatestAnswer(token) * amount;
  }

}
