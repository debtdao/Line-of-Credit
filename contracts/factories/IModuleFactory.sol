pragma solidity 0.8.9;

interface IModuleFactory {

    event DeployedSpigot(
        address indexed spigotAddress,
        address indexed owner,
        address indexed treasury
    );

    event DeployedEscrow(
        address indexed escrowAddress,
        uint32 indexed minCRatio,
        address indexed borrower
    );

    function DeploySpigot(address owner, address treasury, address operator) external returns(address);

    function DeployEscrow(uint32 minCRatio, address oracle, address owner, address borrower) external returns(address);
}