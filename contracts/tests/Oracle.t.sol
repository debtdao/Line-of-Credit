pragma solidity 0.8.9;

import "forge-std/Test.sol";

import "chainlink/interfaces/FeedRegistryInterface.sol";
import {Denominations} from "chainlink/Denominations.sol";
import { Oracle } from "../modules/oracle/Oracle.sol";
import {MockRegistry} from "../mock/MockRegistry.sol";
import {LineOfCredit} from "../modules/credit/LineOfCredit.sol";
import {RevenueToken} from "../mock/RevenueToken.sol";
import {LineLib} from "../utils/LineLib.sol";
import { Escrow } from "../modules/escrow/Escrow.sol";

/*
collateralValue, debtValue (different decimals, same value);

- [x]  Must normalize all oracle prices to 8 decimals
    - [x]  both aggregators in 8 decimals
    - [x]  both above 8 decimals
    - [x]  both below 8 decimals
    - [x]  one 8 decimal, one over 8 decimal
    - [x]  one under 8 decimal, one 9 decimal
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

    int256 constant TOKEN_A_PRICE = 500;
    int256 constant TOKEN_B_PRICE = 750;

    int256 constant DECIMALS_6 = 10**6;
    int256 constant DECIMALS_7 = 10**7;
    int256 constant DECIMALS_8 = 10**8;
    int256 constant DECIMALS_9 = 10**9;
    int256 constant DECIMALS_10 = 10**10;
    


    // Chainlink
    FeedRegistryInterface registry;
    MockRegistry mockRegistry1;
    MockRegistry mockRegistry2;

    address constant feedRegistryAddress = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
    
    uint256 mainnetFork;
    Oracle forkOracle;
    Oracle oracle1;
    Oracle oracle2;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    // Line
    LineOfCredit line;
    Escrow escrow;
    address borrower;
    address arbiter;
    address lender;

    uint256 mintAmount = 100 ether;
    uint32 minCollateralRatio = 10000; // 100%
    uint256 ttl = 150 days;
    uint128 dRate = 100;
    uint128 fRate = 1;

    constructor() {

    }

    function setUp() external {
        // Fork
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        forkOracle = new Oracle(feedRegistryAddress);
        registry = FeedRegistryInterface(feedRegistryAddress);

        // Mocks
        mockRegistry1 = new MockRegistry();
        mockRegistry2 = new MockRegistry();
        
        oracle1 = new Oracle(address(mockRegistry1));
        oracle2 = new Oracle(address(mockRegistry2));

        tokenA = new RevenueToken();
        tokenB = new RevenueToken();

        mockRegistry1.addToken(address(tokenA), TOKEN_A_PRICE);
        mockRegistry1.addToken(address(tokenB), TOKEN_B_PRICE);

        mockRegistry2.addToken(address(tokenA), TOKEN_A_PRICE);
        mockRegistry2.addToken(address(tokenB), TOKEN_B_PRICE);

        // Line
        borrower = address(10);
        arbiter = address(this);
        lender = address(20);

        line = new LineOfCredit(address(oracle1), arbiter, borrower, ttl);
        assertEq(uint256(line.init()), uint256(LineLib.STATUS.ACTIVE));
        
        // deploy and save escrow
        escrow = new Escrow ( minCollateralRatio, address(oracle2), address(line), borrower);
        
        _mintAndApprove();

        _addCreditAndBorrow(address(tokenA), 1 ether);
    }

    /*/////////////////////////////////////////////////////////
    ///////////////         FUZZ TESTS          ///////////////
    /////////////////////////////////////////////////////////*/


    function test_collateral_value_after_decimals_change(uint8 decimalsA, uint8 decimalsB) external {
        vm.assume(decimalsA < 50 && decimalsB < 50);
        vm.warp(block.timestamp + 7 days);

        // before changing the oracle
        (uint256 principal, uint256 interest) = line.updateOutstandingDebt();
        emit log_named_uint("principal", principal);
        emit log_named_uint("interest", interest);

        uint256 collateralValue = escrow.getCollateralValue();
        emit log_named_uint("collateral", collateralValue);

        // after changing the oracle
        mockRegistry1.updateTokenDecimals(address(tokenA), decimalsA);
        mockRegistry2.updateTokenDecimals(address(tokenA), decimalsB);

        uint256 altCollateralValue = escrow.getCollateralValue();
        (uint256 altPrincipal, uint256 altInterest) = line.updateOutstandingDebt();
        
        assertEq(collateralValue, altCollateralValue);
        assertEq(principal, altPrincipal);
        assertEq(interest, altInterest);
    }


    /*/////////////////////////////////////////////////////////
    ///////////////         FORK TESTS          ///////////////
    /////////////////////////////////////////////////////////*/
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

    /*/////////////////////////////////////////////////////////
    ///////////////         MOCK TESTS          ///////////////
    /////////////////////////////////////////////////////////*/

    function test_token_with_stale_price() external {
        mockRegistry1.overrideTokenTimestamp(address(tokenA), true);
        vm.expectEmit(true,false,false, true, address(oracle1));
        emit StalePrice(address(tokenA), block.timestamp - 28 hours);
        int256 price = oracle1.getLatestAnswer(address(tokenA));
        assertEq(price, 0);
    }

    function test_token_with_null_price() external {
        mockRegistry1.updateTokenBasePrice(address(tokenB), 0);
        vm.expectEmit(true,false,false, true, address(oracle1));
        emit NullPrice(address(tokenB));
        int price = oracle1.getLatestAnswer(address(tokenB));
        assertEq(price, 0);
    }

    function test_token_price_with_varying_decimals(uint8 newDecimals) external {
        vm.assume(newDecimals < 50);

        int256 price = oracle1.getLatestAnswer(address(tokenA));
        assertEq(price, TOKEN_A_PRICE * DECIMALS_8);

        uint8 tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, 8);

        mockRegistry1.updateTokenDecimals(address(tokenA), newDecimals);

        tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, newDecimals);

        int256 newPrice = oracle1.getLatestAnswer(address(tokenA));
        assertEq(price, newPrice);
    }

    function test_token_with_zero_decimals() external {

        uint8 tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, 8);
        
        mockRegistry1.updateTokenDecimals(address(tokenA), 0);


        tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, 0);

        int price = oracle1.getLatestAnswer(address(tokenA));

        assertEq(price, TOKEN_A_PRICE * DECIMALS_8);
    }

    function test_token_with_invalid_decimals() external {

        uint8 tokenAdecimals = mockRegistry1.decimals(address(tokenA), address(0));
        assertEq(tokenAdecimals, 8);

        mockRegistry1.revertDecimals(address(tokenA), true);

        bytes memory empty;
        emit NoDecimalData(address(tokenA), empty);
        int price = oracle1.getLatestAnswer(address(tokenA));

        assertEq(price, 0);
    }

    /*/////////////////////////////////////////////////////////
    ///////////////         HELPERS             ///////////////
    /////////////////////////////////////////////////////////*/

     function _mintAndApprove() internal {
        deal(lender, mintAmount);

        tokenA.mint(borrower, mintAmount);
        tokenA.mint(lender, mintAmount);
        tokenB.mint(borrower, mintAmount);
        tokenB.mint(lender, mintAmount);


        vm.startPrank(borrower);
        tokenA.approve(address(line), type(uint256).max);
        tokenB.approve(address(line), type(uint256).max);
        tokenA.approve(address(escrow), type(uint256).max);
        tokenB.approve(address(escrow), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(lender);
        tokenA.approve(address(line), type(uint256).max);
        tokenB.approve(address(line), type(uint256).max);
        vm.stopPrank();
    }   
    
    function _addCreditAndBorrow(address token, uint256 amount) internal {
        vm.startPrank(borrower);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
        vm.startPrank(lender);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

        vm.startPrank(arbiter);
        escrow.enableCollateral(address(token));
        vm.stopPrank();

        vm.startPrank(borrower);
        escrow.addCollateral(1 ether, address(token));
        line.borrow(line.ids(0), 1 ether);
        vm.stopPrank();
    }

}