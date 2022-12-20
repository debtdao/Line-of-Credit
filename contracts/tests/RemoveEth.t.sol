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
import { ISpigotedLine } from '../interfaces/ISpigotedLine.sol';
import { ILineOfCredit } from '../interfaces/ILineOfCredit.sol';


/**
 * @dev -   This file tests functionality relating to the removal of native Eth support
 *      -   and scenarios in which native Eth is generated as revenue
 */
contract RemoveEth is Test {

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
    uint lentAmount = 1 ether;
    
    uint128 constant dRate = 100;
    uint128 constant fRate = 1;
    uint constant ttl = 10 days; // allows us t
    uint8 constant ownerSplit = 10; // 10% of all borrower revenue goes to spigot

    uint constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint constant MAX_REVENUE = MAX_INT / 100;
    uint256 constant REVENUE_EARNED = 10 ether;

    // Line access control vars
    address private arbiter = makeAddr("arbiter");
    address private borrower = makeAddr("borrower");
    address private lender = makeAddr("lender");

    address private testaddr = makeAddr("test");
    SimpleOracle private oracle;

    SecuredLine line;

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

        _mintAndApprove();
        
        _createCredit();

        spigot = line.spigot();

        vm.prank(borrower);
        revenueContract.transferOwnership(address(spigot));
        
    }

    function test_claiming_ETH_as_revenue() public {
        // revenue go brrrrrrr
        // assertTrue(true);
        spigot.claimRevenue(address(revenueContract), Denominations.ETH, abi.encode(SimpleRevenueContract.sendPushPayment.selector));
        assertEq(address(spigot).balance, REVENUE_EARNED);
    }

    function _mintAndApprove() public {
      // ETH
      vm.deal(address(dex), MAX_REVENUE);
      vm.deal(address(borrower), MAX_REVENUE);
      vm.deal(address(lender), MAX_REVENUE);
      
      // seed dex with tokens to buy
      creditToken1.mint(address(dex), MAX_REVENUE);
      creditToken2.mint(address(dex), MAX_REVENUE);

      // allow line to use tokens for depositAndRepay()
      creditToken1.mint(lender, MAX_REVENUE);
      creditToken1.mint(address(this), MAX_REVENUE);
      creditToken1.approve(address(line), MAX_INT);

      creditToken2.mint(lender, MAX_REVENUE);
      creditToken2.mint(address(this), MAX_REVENUE);
      creditToken2.approve(address(line), MAX_INT);

      // allow trades
      creditToken1.approve(address(dex), MAX_INT);
      creditToken2.approve(address(dex), MAX_INT);

      // user approvals
      vm.prank(borrower);
      creditToken1.approve(address(line), MAX_INT);
      vm.prank(lender);
      creditToken1.approve(address(line), MAX_INT);

      // simulate revenue generation
      vm.deal(address(revenueContract), REVENUE_EARNED);
      assertEq(address(revenueContract).balance, REVENUE_EARNED, "balance should be 10 ether");
      
    }

    // Add the ERC20 for borrowing+lending and add revenue stream to the spigot
    function _createCredit() public returns(bytes32 id) {

      ISpigot.Setting memory settings = ISpigot.Setting({
        ownerSplit: ownerSplit,
        claimFunction: SimpleRevenueContract.sendPushPayment.selector,
        transferOwnerFunction: SimpleRevenueContract.transferOwnership.selector
      });

      startHoax(borrower);
      line.addCredit(dRate, fRate, lentAmount, address(creditToken1), lender);
      vm.stopPrank();
      
      startHoax(lender);
      deal(address(creditToken1), lender, MAX_REVENUE);
      id = line.addCredit(dRate, fRate, lentAmount, address(creditToken1), lender);
      vm.stopPrank();

      // as arbiter
      hoax(arbiter);
      line.addSpigot(address(revenueContract), settings);
      vm.stopPrank();
    }



    // TODO: test WETH/ETH price using fork oracle
}