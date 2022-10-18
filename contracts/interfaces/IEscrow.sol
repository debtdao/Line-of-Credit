pragma solidity 0.8.9;

interface IEscrow {
    struct Deposit {
        uint256 amount;
        bool isERC4626;
        address asset; // eip4626 asset else the erc20 token itself
        uint8 assetDecimals;
    }

    event AddCollateral(address indexed token, uint256 indexed amount);

    event RemoveCollateral(address indexed token, uint256 indexed amount);

    event EnableCollateral(address indexed token);

    error InvalidCollateral();

    error CallerAccessDenied();

    error UnderCollateralized();

    error NotLiquidatable();

    // State var etters.

    function line() external returns (address);

    function oracle() external returns (address);

    function borrower() external returns (address);

    function minimumCollateralRatio() external returns (uint32);

    // Functions

    function isLiquidatable() external returns (bool);

    function updateLine(address line_) external returns (bool);

    function getCollateralRatio() external returns (uint256);

    function getCollateralValue() external returns (uint256);

    function enableCollateral(address token) external returns (bool);

    function addCollateral(uint256 amount, address token) external payable returns (uint256);

    function releaseCollateral(uint256 amount, address token, address to) external returns (uint256);

    function liquidate(uint256 amount, address token, address to) external returns (bool);
}
