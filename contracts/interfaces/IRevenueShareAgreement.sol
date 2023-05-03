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
    error InsufficientAllowance(address, address, uint256, uint256);

    event log_named_uint2(string err, uint256 val);

    event TradeInitiated(
        bytes32 indexed tradeHash,
        uint256 indexed sellAmount,
        uint256 indexed minBuyAmount,
        uint256 deadline
    );

    event Redeem(
        address indexed receiver,
        address indexed owner,
        address indexed caller,
        uint256 amount
    );


    event Deposit(address indexed lender);
    event TradeFinalized(bytes32 indexed tradeHash);

}