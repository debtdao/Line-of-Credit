interface ISpigot {
    function claimRevenue(address revenueContract, bytes calldata data) external returns(uint256);
    function claimEscrow(address token) external returns(uint256);
    function getEscrowBalance(address token) external returns(uint256);
    function operate(address revenueContract, bytes calldata data) external returns(bool);
    function doOperations(address[] calldata contracts, bytes[] calldata data) external returns(bool);
    function removeSpigot(address revenueContract) external returns(bool);
    function updateOwnerSplit(address revenueContract, uint8 newSplit) external returns(bool);
    function updateOwner(address newOwner) external returns(bool);
    function updateOperator(address newOperator) external returns(bool);
    function updateTreasury(address newTreasury) external returns(bool);
    function getSetting(address revenueContract) external returns(address, uint8, bytes4, bytes4);
}
