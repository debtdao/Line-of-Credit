interface ISpigot {

    struct Setting {
        address token;                // token to claim as revenue from contract
        uint8 ownerSplit;             // x/100 % to Owner, rest to Treasury
        bytes4 claimFunction;         // function signature on contract to call and claim revenue
        bytes4 transferOwnerFunction; // function signature on conract to call and transfer ownership 
    }

    // Spigot Events

    event AddSpigot(address indexed revenueContract, address token, uint256 ownerSplit);

    event RemoveSpigot (address indexed revenueContract, address token);

    event UpdateWhitelistFunction(bytes4 indexed func, bool indexed allowed);

    event UpdateOwnerSplit(address indexed revenueContract, uint8 indexed split);

    event ClaimRevenue(address indexed token, uint256 indexed amount, uint256 escrowed, address revenueContract);

    event ClaimEscrow(address indexed token, uint256 indexed amount, address owner);

    // Stakeholder Events

    event UpdateOwner(address indexed newOwner);

    event UpdateOperator(address indexed newOperator);

    event UpdateTreasury(address indexed newTreasury);

    // Errors 
    error BadFunction();

    error ClaimFailed();

    error NoRevenue();

    error CallerAccessDenied();
    
    error BadSetting();

}
