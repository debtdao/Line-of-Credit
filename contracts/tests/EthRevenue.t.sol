pragma solidity 0.8.9;

import "forge-std/Test.sol";


import { Denominations } from "chainlink/Denominations.sol";
import { ZeroEx } from "../mock/ZeroEx.sol";
import { SimpleOracle } from "../mock/SimpleOracle.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";
import {SimpleRevenueContract} from "../mock/SimpleRevenueContract.sol";
import {LineFactory} from "../modules/factories/LineFactory.sol";
import {ModuleFactory} from "../modules/factories/ModuleFactory.sol";
import { Spigot } from "../modules/spigot/Spigot.sol";
import { SpigotedLine } from '../modules/credit/SpigotedLine.sol';
import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import { LineLib } from '../utils/LineLib.sol';
import { SpigotedLineLib } from '../utils/SpigotedLineLib.sol';
import { ISpigot } from '../interfaces/ISpigot.sol';
import { IEscrow } from '../interfaces/IEscrow.sol';
import { ISpigotedLine } from '../interfaces/ISpigotedLine.sol';
import { ILineOfCredit } from '../interfaces/ILineOfCredit.sol';


/**
 * @dev -   This file tests functionality relating to the removal of native Eth support
 *      -   and scenarios in which native Eth is generated as revenue
 */
contract EthRevenue is Test {

    ModuleFactory moduleFactory;
    LineFactory lineFactory;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    ZeroEx dex;
    ISpigot spigot;

    RevenueToken creditToken1;
    RevenueToken creditToken2;

    // Named vars for common inputs
    SimpleRevenueContract revenueContract;
    uint lentAmounUSD = 100_000; // (50 Eth at $2000/Eth)
    uint lentAmountTokens = 50 ether;

    uint128 constant dRate = 100;
    uint128 constant fRate = 1;
    uint constant ttl = 150 days; // allows us t
    uint8 constant ownerSplit = 10; // 10% of all borrower revenue goes to onwer (line of credit)

    uint256 MAX_INT = type(uint256).max;
    uint256 constant REVENUE_EARNED_USD = 200_000; // (100 Eth at $2000/Eth)
    uint256 constant REVENUE_EARNED_ETH = 100 ether;
    
    // Line access control vars
    address private arbiter = makeAddr("arbiter");
    address private borrower = makeAddr("borrower");
    address private lender = makeAddr("lender");
    address private testaddr = makeAddr("test");
    
    SimpleOracle private oracle;
    SecuredLine line;
    IEscrow escrow;

    // local variables to avoid stackTooDeep
    uint256 claimed;
    uint256 ownerTokens;
    uint256 operatorTokens;
    uint256 borrowerBalance;
    uint256 principalUSD;
    uint256 interestUSD;
    uint256 outstandingDebtUSD;
    int256 creditTokenPriceUSD;
    uint256 outstandingDebtTokens;

    function setUp() public {

        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        dex = new ZeroEx();
        creditToken1 = new RevenueToken();
        creditToken2 = new RevenueToken();

        revenueContract = new SimpleRevenueContract(borrower, Denominations.ETH);

        // Eth price is set to 2000 * 1e8 by default
        oracle = new SimpleOracle(address(creditToken1), address(creditToken2));

        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(address(moduleFactory), arbiter, address(oracle), payable(address(dex)));

        address securedLine = lineFactory.deploySecuredLine(borrower, ttl);

        line = SecuredLine(payable(securedLine));


        spigot = line.spigot();
        escrow = line.escrow();

        _mintAndApprove();
        
        _createCredit();

        vm.prank(borrower);
        revenueContract.transferOwnership(address(spigot));
        
    }

    /*////////////////////////////////////////////////
    ////////////////    TESTS   //////////////////////
    ////////////////////////////////////////////////*/

    // test claiming native eth from the revenue contract
    function test_claiming_ETH_as_revenue() public {
        // revenue go brrrrrrr
        spigot.claimRevenue(address(revenueContract), Denominations.ETH, abi.encode(SimpleRevenueContract.sendPushPayment.selector));
        assertEq(address(spigot).balance, REVENUE_EARNED_ETH);
    }

  
    function test_claiming_and_trading_ETH_revenue_for_credit_tokens() public {
      
      assertEq(address(spigot).balance, 0);

      // Claim Revenue

      claimed = spigot.claimRevenue(address(revenueContract), Denominations.ETH, abi.encode(SimpleRevenueContract.sendPushPayment.selector));
      ownerTokens = spigot.getOwnerTokens(Denominations.ETH);
      operatorTokens = spigot.getOperatorTokens(Denominations.ETH);

      assertEq(claimed, ownerTokens + operatorTokens, "token split should add up to total claimed");
      assertEq(address(spigot).balance, REVENUE_EARNED_ETH, "spigot balance should equal earned revenue");
      assertEq(address(revenueContract).balance, 0, "revenue contract balance should be zero");
      assertEq(claimed, REVENUE_EARNED_ETH, "claimable should equal earned revenue");

      // Claim operator Tokens

      // withdraw the operator tokens, ie the borrower retrieves 90% of the Eth revenue
      borrowerBalance = borrower.balance;
      vm.startPrank(borrower);
      spigot.claimOperatorTokens(Denominations.ETH);
      vm.stopPrank();

      assertEq(borrower.balance, borrowerBalance + operatorTokens, "borrowers ETH balance increases after claiming operator tokens");
      assertEq(address(spigot).balance, ownerTokens, " spigot balance should be equal to only the ownerTokens");

      // warp forward to generate some interest
      vm.warp(block.timestamp + 36.25 days);

      (principalUSD, interestUSD) = line.updateOutstandingDebt();
      outstandingDebtUSD = principalUSD + interestUSD;
      creditTokenPriceUSD = oracle.getLatestAnswer(address(creditToken1));
      outstandingDebtTokens = (outstandingDebtUSD / uint256(creditTokenPriceUSD)) * 10**8;

      uint256 ownerTokenValueInCreditToken = ownerTokens / uint256(oracle.getLatestAnswer(address(creditToken1)));
      emit log_named_uint("outstandingDebtUSD", outstandingDebtUSD);
      emit log_named_uint("ownerTokenValueInCreditToken", ownerTokenValueInCreditToken);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        Denominations.ETH, // token in
        address(creditToken1), // token out
        ownerTokens, // in amount
        outstandingDebtTokens // out amount
      );

      // vm.prank(arbiter);
      // uint256 tokensBought = line.claimAndTrade(Denominations.ETH, tradeData); // NOTE: uncomment this <===
      // emit log_named_uint("tokens bought", tokensBought);

      // assertEq(address(spigot).balance, 0);


      // emit log_named_uint("[after] line unused eth    ", line.unused(Denominations.ETH));
      // emit log_named_uint("[after] line unused tokens ", line.unused(address(creditToken1)));
      // emit log_named_uint("[after] line token balance ", creditToken1.balanceOf(address(line)));

      // emit log_named_uint("[after] spigot eth balance ", address(spigot).balance );
      // emit log_named_uint("[after] line eth balance   ", address(line).balance );


      // uint256 lenderBalanceBefore = creditToken1.balanceOf(lender);
      // emit log_named_uint("lenderBalanceBefore", lenderBalanceBefore);
      // // use the unused credit tokens to repay some debt

      // assertGt(line.unused(address(creditToken1)), outstandingDebtUSD);

      // emit log_string("===== use And Repay =====");
      // emit log_string(" ");

      // vm.prank(borrower);
      // line.useAndRepay(outstandingDebtUSD);

      // uint256 unusedCreditTokensRemaining = line.unused(address(creditToken1));

      // vm.startPrank(lender);
      // line.withdraw(line.ids(0), unusedCreditTokensRemaining);
      // vm.stopPrank();

      // uint256 lenderBalanceAfter = creditToken1.balanceOf(lender);
      // emit log_named_uint("lenderBalanceAfter", lenderBalanceAfter);

      // assertEq(lenderBalanceBefore, lenderBalanceAfter + unusedCreditTokensRemaining);

      // uint256 unused = line.unused(address(creditToken1));
      // emit log_named_uint("unused", unused);

      // ( uint256 newPrincipal,  uint256 newInterest) = line.updateOutstandingDebt();
      // emit log_named_uint("newPrincipal", newPrincipal);
      // emit log_named_uint("newInterest", newInterest);

      // ownerTokens = spigot.getOwnerTokens(Denominations.ETH);
      // emit log_named_uint("ownerTokens", ownerTokens);

      // emit log_named_uint("[after] line unused eth    ", line.unused(Denominations.ETH));
      // emit log_named_uint("[after] line unused tokens ", line.unused(address(creditToken1)));
      // emit log_named_uint("[after] line token balance ", creditToken1.balanceOf(address(line)));

      // emit log_named_uint("[after] spigot eth balance ", address(spigot).balance );
      // emit log_named_uint("[after] line eth balance   ", address(line).balance );

    }

    /*////////////////////////////////////////////////
    ////////////////    UTILS   //////////////////////
    ////////////////////////////////////////////////*/


    function _mintAndApprove() public {
      // ETH
      vm.deal(address(dex), MAX_INT);
      vm.deal(address(borrower), 0);
      vm.deal(address(lender), lentAmountTokens);
      
      // seed dex with tokens to buy
      creditToken1.mint(address(dex), MAX_INT / 2);
      creditToken1.mint(address(borrower), lentAmountTokens / 2); // for collateral

      // allow line to use tokens for depositAndRepay()
      creditToken1.mint(lender, lentAmountTokens);
      creditToken1.approve(address(line), MAX_INT);
      // allow trades
      creditToken1.approve(address(dex), MAX_INT);

      // user approvals
      vm.startPrank(borrower);
      creditToken1.approve(address(line), MAX_INT);
      creditToken1.approve(address(escrow), MAX_INT);
      vm.stopPrank();

      vm.prank(lender);
      creditToken1.approve(address(line), MAX_INT);

      // simulate revenue generation
      vm.deal(address(revenueContract), REVENUE_EARNED_ETH);
      assertEq(address(revenueContract).balance, REVENUE_EARNED_ETH, "balance should be 10 ether");
      
    }

    // Add the ERC20 for borrowing+lending and add revenue stream to the spigot
    function _createCredit() public returns(bytes32 id) {

      // simulate stable coin price of 1 USD
      oracle.changePrice(address(creditToken1), 1 * 1e8);

      ISpigot.Setting memory settings = ISpigot.Setting({
        ownerSplit: ownerSplit,
        claimFunction: SimpleRevenueContract.sendPushPayment.selector,
        transferOwnerFunction: SimpleRevenueContract.transferOwnership.selector
      });

      emit log_string("enable collateral");

      vm.startPrank(arbiter);
      escrow.enableCollateral(address(creditToken1));
      vm.stopPrank();

      emit log_string("adding Collateral");

      vm.startPrank(borrower);
      escrow.addCollateral(lentAmountTokens / 2, address(creditToken1));
      line.addCredit(dRate, fRate, lentAmountTokens, address(creditToken1), lender);
      vm.stopPrank();

      emit log_named_uint("collateral value", escrow.getCollateralValue());
      
      startHoax(lender);
      id = line.addCredit(dRate, fRate, lentAmountTokens, address(creditToken1), lender);
      vm.stopPrank();

      // as arbiter
      hoax(arbiter);
      line.addSpigot(address(revenueContract), settings);
      vm.stopPrank();

      emit log_string("borrowing");
      vm.startPrank(borrower);
      line.borrow(line.ids(0), lentAmountTokens);
      vm.stopPrank();

      int256 ethPrice = oracle.getLatestAnswer(Denominations.ETH);
      emit log_named_int("[create ethPrice] ethPrice", ethPrice);

      int256 creditTokenPrice = oracle.getLatestAnswer(address(creditToken1));
      emit log_named_int("[create credit] creditTokenPrice", creditTokenPrice);

      (uint256 principal, uint256 interest) = line.updateOutstandingDebt();
      emit log_named_uint("[create credit] principal", principal);
      emit log_named_uint("[create credit] interest", interest);
    }

    function _convertUsdToEthToken(uint256 usd) internal returns (uint256){
      int256 ethPriceUSD = oracle.getLatestAnswer(Denominations.ETH);
      return uint256(ethPriceUSD) * usd;
    }

    function _convertUsdToCreditTokens(uint256 usd) internal returns (uint256) {
      int256 tokenPriceUSD = oracle.getLatestAnswer(address(creditToken1));
      return uint256(tokenPriceUSD) * usd;
    }

}