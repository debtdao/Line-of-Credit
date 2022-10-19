pragma solidity 0.8.9;

interface ILineFactory {
    event DeployedSecuredLine(
        address indexed deployedAt,
        address indexed escrow,
        address indexed spigot,
        address swapTarget,
        uint8 revenueSplit
    );

    error ModuleTransferFailed(address line, address spigot, address escrow);
    error InvalidRevenueSplit();

    function deployEscrow(
        uint32 minCRatio,
        address owner,
        address borrower
    ) external returns (address);

    function deploySpigot(
        address owner,
        address borrower,
        address operator
    ) external returns (address);

    function deploySecuredLine(address borrower, uint256 ttl)
        external
        returns (address);

    function deploySecuredLineWithConfig(
        address borrower,
        uint256 ttl,
        uint8 revenueSplit,
        uint32 cratio
    ) external returns (address);

    function rolloverSecuredLine(
        address payable oldLine,
        address borrower,
        uint256 ttl
    ) external returns (address);
}
