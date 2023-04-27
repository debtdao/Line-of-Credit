pragma solidity ^0.8.16;

interface IRSAFactory {
    function createRSA(
        address _spigot,
        address _borrower,
        address _creditToken,
        uint8 _revenueSplit,
        uint256 _initialPrincipal,
        uint256 _totalOwed,
        string memory _name,
        string memory _symbol
    ) external returns(address);

    // move to factory
    event DeployRSA(
        address indexed borrower,
        address indexed spigot,
        address indexed creditToken,
        uint256 initialPrinciple,
        uint256 totalOwed,
        uint8 lenderRevenueSplit
    );
}