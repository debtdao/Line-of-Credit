pragma solidity 0.8.16;

interface IRevenueShareAgreement { 
    
    error InvalidPaymentSetting();
    error InvalidRevenueSplit();
    error CantSweepWhileInDebt();
    error DepositsFull();
    error InvalidTradeId();
    error InvalidTradeData();
    error ExceedClaimableTokens(uint256 claimable);
    error NotBorrower();
    error AlreadyInitialized();
    error InvalidSpigotAddress();
    error InvalidBorrowerAddress();
    error InvalidTradeDomain();
    error InvalidTradeDeadline();
    error InvalidTradeTokens();
    error InvalidTradeBalanceDestination();
    error MustBeSellOrder();
    error WETHDepositFailed();
    error NotLender();
    error MustSellMoreThan0();
    error InvalidWETHDeposit();
    error InsufficientAllowance();

    event log_named_uint2(string err, uint256 val);

    event OrderInitiated(
        address indexed creditToken,
        address indexed revenueToken,
        bytes32 tradeHash,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint32 validTo
    );

    event Repay(uint256 amount);

    event Redeem(
        address indexed receiver,
        address indexed owner,
        address indexed caller,
        uint256 amount
    );


    event Deposit(address indexed lender);
    event TradeFinalized(bytes32 indexed tradeHash);

}