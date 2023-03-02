// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { ISpigot } from "../contracts/interfaces/ISpigot.sol";
import { ISecuredLine } from "../contracts/interfaces/ISecuredLine.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

contract ViewLineAssets is Script {
    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 initialBlockNumber = 16713945;

    function run() external {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        mainnetFork = vm.createFork(MAINNET_RPC_URL, initialBlockNumber);
        vm.selectFork(mainnetFork);
        vm.startBroadcast();

        ISecuredLine line =ISecuredLine(vm.envAddress("OBSERVABLE_LINE"));
        ISpigot spigot = ISpigot(line.spigot());
        // get line address from env
        // revenue
        address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        address eth = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        // credit
        address dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        // collateral
        // address snx = address(0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F);
        
        uint256 usdcBalance1 = spigot.getOperatorTokens(usdc);
        uint256 usdcBalance2 = spigot.getOwnerTokens(usdc);
        uint256 usdcBalance3 = line.unused(usdc);
        uint256 usdcBalance4 = IERC20(usdc).balanceOf(address(spigot));
        
        uint256 ethBalance1 = spigot.getOperatorTokens(eth);
        uint256 ethBalance2 = spigot.getOwnerTokens(eth);
        uint256 ethBalance3 = line.unused(eth);

        uint256 daiBalance1 = IERC20(dai).balanceOf(address(line));
        uint256 daiBalance3 = line.unused(dai);
        uint256 usdcBalance5 = line.unused(usdc);

        console.log('Spigot Ops USDC: ', usdcBalance1);
        console.log('Spigot Owner USDC: ', usdcBalance2);
        console.log('Line Unused USDC: ', usdcBalance3);
        console.log('Total Spigot USDC: ', usdcBalance4);

        console.log('Spigot Ops ETH: ', ethBalance1);
        console.log('Spigot Owner ETH: ', ethBalance2);
        console.log('Line Unused ETH: ', ethBalance3);
        
        console.log('Line DAI balance: ', daiBalance1);
        console.log('Line Unused DAI: ', daiBalance3);
        console.log('Line Unused USDC: ', usdcBalance5);

        // get spigot
        // output spigt operator / owner
        // outpute line reserves
        // output line available credit (balance - reserves)
        // output escrow deposits
        vm.stopBroadcast();
    }
}