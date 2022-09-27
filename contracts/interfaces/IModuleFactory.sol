pragma solidity 0.8.9;

interface IModuleFactory {

    event DeployedSpigot(
        address indexed deployedAt,
        address indexed owner,
        address indexed treasury,
        address operator
    );

    event DeployedEscrow(
        address indexed deployedAt,
        uint32 indexed minCRatio,
        address indexed oracle,
        address owner
    );

    function deploySpigot(address owner, address treasury, address operator) external returns(address);

    function deployEscrow(uint32 minCRatio, address oracle, address owner, address borrower) external returns(address);
}
