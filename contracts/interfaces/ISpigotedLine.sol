pragma solidity ^0.8.9;

import {ISpigot} from "./ISpigot.sol";

interface ISpigotedLine {
    // @notice Log how many revenue tokens are used to repay debt after claimAndRepay
    // dont need to track value like other events because _repay already emits that
    // Mainly used to log debt that is paid via Spigot directly vs other sources. Without this event it's a lot harder to parse that offchain.
    event RevenuePayment(address indexed token, uint256 indexed amount);

    // @notice Log many revenue tokens were traded for credit tokens.
    // @notice differs from Revenue Payment because we trade revenue at different times from repaying with revenue
    // @dev Can you use to figure out price of revenue tokens offchain since we only have an oracle for credit tokens
    // @dev Revenue tokens might be reserves or just claimed from Spigot.
    event TradeSpigotRevenue(
        address indexed revenueToken,
        uint256 revenueTokenAmount,
        address indexed debtToken,
        uint256 indexed debtTokensBought
    );

    // Borrower functions
    function useAndRepay(uint256 amount) external returns (bool);

    function claimAndRepay(address token, bytes calldata zeroExTradeData)
        external
        returns (uint256);

    function claimAndTrade(address token, bytes calldata zeroExTradeData)
        external
        returns (uint256 tokensBought);

    // Manage Spigot functions
    function addSpigot(
        address revenueContract,
        ISpigot.Setting calldata setting
    ) external returns (bool);

    function updateWhitelist(bytes4 func, bool allowed) external returns (bool);

    function updateOwnerSplit(address revenueContract) external returns (bool);

    function releaseSpigot() external returns (bool);

    function sweep(address to, address token) external returns (uint256);

    // getters
    function unused(address token) external returns (uint256);

    function spigot() external returns (ISpigot);
}
