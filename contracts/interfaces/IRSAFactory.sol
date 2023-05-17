pragma solidity ^0.8.16;

interface IRSAFactory {
    function deployRSA(
        address _borrower,
        address _spigot,
        address _creditToken,
        uint8 _revenueSplit,
        uint256 _initialPrincipal,
        uint256 _totalOwed,
        string memory _name,
        string memory _symbol
    ) external returns(address);

    // move to factory
    event DeployedRSA(
        address indexed borrower,
        address indexed spigot,
        address indexed creditToken,
        address rsa,
        uint256 initialPrincipal,
        uint256 totalOwed,
        uint8 lenderRevenueSplit
    );

    event DeployedSpigot(address spigot, address indexed owner, address indexed operator);
}