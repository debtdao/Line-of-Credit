pragma solidity 0.8.9;

import "forge-std/Test.sol";

import "chainlink/interfaces/FeedRegistryInterface.sol";
import {Denominations} from "chainlink/Denominations.sol";
import { Oracle } from "../modules/oracle/Oracle.sol";

/*
- [ ]  Must normalize all oracle prices to 8 decimals
    - [ ]  both aggregators in 8 decimals
    - [ ]  both above 8 decimals
    - [ ]  both below 8 decimals
    - [ ]  one 8 decimal, one over 8 decimal
    - [ ]  one under 8 decimal, one 9 decimal
- [ ]  Price must be within 2 hours
- [x]  price must be > 0
- [x]  oracle reverts if address is not an erc20
*/

interface Events {
    event StalePrice(address indexed token);
    event NullPrice(address indexed token);
    event NoDecimalData(address indexed token);
    event NoRoundData(address indexed token, string err);
}
contract OracleTest is Test, Events {

    // Tokens
    address constant linkToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant btc = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    address constant ampl = 0xD46bA6D942050d489DBd938a2C909A5d5039A161;

    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
    
    uint256 mainnetFork;
    Oracle oracle;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() external {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        oracle = new Oracle(feedRegistry);
    }

    function test_fetching_known_token_returns_valid_price() external {
        vm.selectFork(mainnetFork);
        int256 linkPrice = oracle.getLatestAnswer(linkToken);
        emit log_named_int("link", linkPrice);
        assertGt(linkPrice, 0);
    }

    function test_fails_if_address_is_not_ERC20_token() external {
        vm.selectFork(mainnetFork);
        address nonToken = makeAddr("notAtoken");
        // vm.expectEmit(true,true,false,true, address(oracle));
        // emit NoRoundData(nonToken, "Feed not Found");
        int256 price = oracle.getLatestAnswer(nonToken);
        assertEq(price, 0);
    }


}