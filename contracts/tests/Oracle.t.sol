pragma solidity 0.8.9;

import "forge-std/Test.sol";

import "chainlink/interfaces/FeedRegistryInterface.sol";
import {Denominations} from "chainlink/Denominations.sol";
import { Oracle } from "../modules/oracle/Oracle.sol";
import {MockRegistry} from "../mock/MockRegistry.sol";

import {RevenueToken} from "../mock/RevenueToken.sol";


/*
collateralValue, debtValue (different decimals, same value);

- [ ]  Must normalize all oracle prices to 8 decimals
    - [ ]  both aggregators in 8 decimals
    - [ ]  both above 8 decimals
    - [ ]  both below 8 decimals
    - [ ]  one 8 decimal, one over 8 decimal
    - [ ]  one under 8 decimal, one 9 decimal
- [x]  Price must be within 25 hours
- [x]  price must be > 0
- [x]  forkOracle reverts if address is not an erc20
*/

interface Events {
    event StalePrice(address indexed token, uint256 answerTimestamp);
    event NullPrice(address indexed token);
    event NoDecimalData(address indexed token, bytes errData);
    event NoRoundData(address indexed token, bytes errData);
}
contract OracleTest is Test, Events {

    // Mainnet Tokens
    address constant linkToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant btc = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    address constant ampl = 0xD46bA6D942050d489DBd938a2C909A5d5039A161;

    // Mock Tokens
    RevenueToken tokenA;
    RevenueToken tokenB;
    int256 constant DECIMALS_8 = 10**8;
    int256 constant DECIMALS_6 = 10**6;
    int256 constant DECIMALS_10 = 10**10;
    int256 constant TOKEN_A_PRICE = 500;
    int256 constant TOKEN_B_PRICE = 750;

    // Chainlink
    FeedRegistryInterface registry;
    MockRegistry mockRegistry1;
    MockRegistry mockRegistry2;

    address constant feedRegistryAddress = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
    
    uint256 mainnetFork;
    Oracle forkOracle;
    Oracle mockOracle1;
    Oracle mockOracle2;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() external {
        // Fork
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        forkOracle = new Oracle(feedRegistryAddress);
        registry = FeedRegistryInterface(feedRegistryAddress);

        // Mocks
        mockRegistry1 = new MockRegistry();
        mockRegistry2 = new MockRegistry();
        
        mockOracle1 = new Oracle(address(mockRegistry1));
        mockOracle2 = new Oracle(address(mockRegistry2));

        tokenA = new RevenueToken();
        tokenB = new RevenueToken();

        mockRegistry1.addToken(address(tokenA), TOKEN_A_PRICE * DECIMALS_8);
        mockRegistry1.addToken(address(tokenB), TOKEN_B_PRICE * DECIMALS_8);

        mockRegistry2.addToken(address(tokenA), TOKEN_A_PRICE * DECIMALS_6);
        mockRegistry2.addToken(address(tokenB), TOKEN_B_PRICE * DECIMALS_10);

    }

    function test_fetching_known_token_returns_valid_price() external {
        vm.selectFork(mainnetFork);
        int256 linkPrice = forkOracle.getLatestAnswer(linkToken);
        emit log_named_int("link", linkPrice);
        assertGt(linkPrice, 0);
    }

    function test_fails_if_address_is_not_ERC20_token() external {
        vm.selectFork(mainnetFork);
        address nonToken = makeAddr("notAtoken");
        vm.expectEmit(false,false,false,false, address(forkOracle));
        emit NoRoundData(nonToken, "Feed not Found");
        int256 price = forkOracle.getLatestAnswer(nonToken);
        assertEq(price, 0);
    }

    // TODO: test mainnet token with less than 8 decimals
    function test_token_with_less_than_8_decimals() external {
        uint256 btcDecimals = registry.decimals(btc, Denominations.USD);
        emit log_named_uint("btc decimals", btcDecimals);
    }

    function test_token_with_more_than_8_decimals() external {
        uint256 amplDecimals = registry.decimals(ampl, Denominations.USD);
        assertEq(amplDecimals, 18);
        (,int256 normalPrice,,,) = registry.latestRoundData(ampl, Denominations.USD);
        int256 price = forkOracle.getLatestAnswer(ampl);
        assertEq(price, normalPrice / 10**10);
    }

    function test_token_with_stale_price() external {
        mockRegistry1.overrideTokenTimestamp(address(tokenA), true);
        vm.expectEmit(true,false,false, true, address(mockOracle1));
        emit StalePrice(address(tokenA), block.timestamp - 28 hours);
        int256 price = mockOracle1.getLatestAnswer(address(tokenA));
        assertEq(price, 0);
    }

    function test_token_with_null_price() external {
        mockRegistry1.updateTokenPrice(address(tokenB), 0);

        vm.expectEmit(true,false,false, true, address(mockOracle1));
        emit NullPrice(address(tokenB));
        int price = mockOracle1.getLatestAnswer(address(tokenB));
        assertEq(price, 0);
    }

    function test_token_price_with_fewer_than_8_decimals() external {
        int256 price = mockOracle1.getLatestAnswer(address(tokenA));
        assertEq(price, TOKEN_A_PRICE * DECIMALS_8);
        uint8 tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        
        assertEq(tokenAdecimals, 8);

        mockRegistry1.updateTokenPrice(address(tokenA), TOKEN_A_PRICE * DECIMALS_6);
        mockRegistry1.updateTokenDecimals(address(tokenA), 6);

        tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, 6);

        int256 newPrice = mockOracle1.getLatestAnswer(address(tokenA));
        assertEq(price, newPrice);
    }

    function test_token_price_with_greater_than_8_decimals() external {
        int256 price = mockOracle1.getLatestAnswer(address(tokenB));
        assertEq(price, TOKEN_B_PRICE * DECIMALS_8);
        uint8 tokenBdecimals = mockRegistry1.decimals(address(tokenB), address(0));
        
        assertEq(tokenBdecimals, 8);

        mockRegistry1.updateTokenPrice(address(tokenB), TOKEN_B_PRICE * DECIMALS_10);
        mockRegistry1.updateTokenDecimals(address(tokenB), 10);

        tokenBdecimals = mockRegistry1.decimals(address(tokenB), address(0));
        assertEq(tokenBdecimals, 10);

        int256 newPrice = mockOracle1.getLatestAnswer(address(tokenB));
        assertEq(price, newPrice);
    }

    function test_token_with_zero_decimals() external {

        uint8 tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, 8);
        
        mockRegistry1.updateTokenPrice(address(tokenA), TOKEN_A_PRICE);
        mockRegistry1.updateTokenDecimals(address(tokenA), 0);


        tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, 0);

        int price = mockOracle1.getLatestAnswer(address(tokenA));

        assertEq(price, TOKEN_A_PRICE * DECIMALS_8);
    }

    function test_token_with_invalid_decimals() external {

        uint8 tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, 8);

        mockRegistry1.revertDecimals(address(tokenA), true);

        bytes memory empty;
        emit NoDecimalData(address(tokenA), empty);
        int price = mockOracle1.getLatestAnswer(address(tokenA));

        assertEq(price, 0);
    }

}