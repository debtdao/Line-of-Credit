pragma solidity 0.8.9;

import "forge-std/Test.sol";

contract RemoveEth is Test {

    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
    }

    function test_max_int() public {
            uint256 MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
            assertEq(MAX_INT, type(uint256).max);
    }

    // TODO: test WETH/ETH price using fork oracle
}