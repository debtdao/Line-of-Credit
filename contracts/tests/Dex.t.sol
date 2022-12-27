pragma solidity 0.8.9;

import "forge-std/Test.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import { Denominations } from "chainlink/Denominations.sol";
import { ZeroEx } from "../mock/ZeroEx.sol";
import { SimpleOracle } from "../mock/SimpleOracle.sol";
import { Oracle } from "../modules/oracle/Oracle.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";
import {SimpleRevenueContract} from "../mock/SimpleRevenueContract.sol";
import {ILineFactory} from "../interfaces/ILineFactory.sol";
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

    Oracle oracle;
    SecuredLine line;

    IEscrow escrow;
    ISpigot spigot;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    RevenueToken creditToken1;
    RevenueToken creditToken2;

    // Named vars for common inputs
    SimpleRevenueContract revenueContract;
    
    uint128 constant dRate = 100;
    uint128 constant fRate = 1;
    uint constant ttl = 150 days; // allows us t
    uint8 constant ownerSplit = 10; // 10% of all borrower revenue goes to spigot

    uint constant MAX_INT = type(uint256).max;
    uint constant MAX_REVENUE = MAX_INT / 100;
    uint256 constant REVENUE_EARNED = 100 ether;

    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf; // Chainlink
    address constant swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // 0x
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Line access control vars
    address private arbiter = makeAddr("arbiter");
    address private borrower = makeAddr("borrower");
    address private lender = makeAddr("lender");
    address anyone = makeAddr("anyone");
    

    uint256 constant initialBlockNumber = 16_082_690; // Nov-30-2022 12:05:23 PM +UTC
    uint256 constant finalBlockNumber = 16_155_490; // Dec-24-2022 03:28:23 PM +UTC

    uint256 constant BORROW_AMOUNT_DAI = 10_000 * 10**18; // $10k USD

    // local vars to prevent stack too deep
    int256 ethPrice;
    int256 daiPrice;
    uint256 tokensBought;
    uint256 ownerTokens;
    uint256 debtUSD;
    uint256 interest;
    uint256 numTokensToRepayDebt;
    uint256 unusedTradedTokens;

    // credit position
    bytes32 id;
    uint256 deposit;
    uint256 principal;
    uint256 interestAccrued;
    uint256 interestRepaid;
    address creditLender;
    bool isOpen;




    /**
        In this scenario, a borrower borrows ~$10k worth of DAI (10k DAI).
        Interest is accrued over 24 hours.
        Revenue of 100 Eth is claimed from the revenue contract.
        10% (10 Eth) is stored in spigot as owner tokens.
        90% (90 Eth) is stored in spigot as operator tokens.
        10 Eth is claimed from the Spigot and traded for DAI.
    */

    function setUp() public {
        
        // create fork at specific block (16_082_690) so we always know the price
        mainnetFork = vm.createFork(MAINNET_RPC_URL, initialBlockNumber);
        vm.selectFork(mainnetFork);

        oracle = new Oracle(feedRegistry);

        revenueContract = new SimpleRevenueContract(borrower, Denominations.ETH);

        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(address(moduleFactory), arbiter, address(oracle), payable(swapTarget));

        ILineFactory.CoreLineParams memory params = ILineFactory.CoreLineParams({
            borrower: borrower,
            ttl: ttl,
            cratio: 0,
            revenueSplit: ownerSplit
        });

        address securedLine = lineFactory.deploySecuredLineWithConfig(params);

        line = SecuredLine(payable(securedLine));

        spigot = line.spigot();
        escrow = line.escrow();

        vm.prank(borrower);
        revenueContract.transferOwnership(address(spigot));

        ISpigot.Setting memory settings = ISpigot.Setting({
            ownerSplit: ownerSplit,
            claimFunction: SimpleRevenueContract.sendPushPayment.selector,
            transferOwnerFunction: SimpleRevenueContract.transferOwnership.selector
        });

        hoax(arbiter);
        line.addSpigot(address(revenueContract), settings);
        vm.stopPrank();

        _setupSimulation();
        
    }

    /*////////////////////////////////////////////////
    ////////////////    TESTS   //////////////////////
    ////////////////////////////////////////////////*/

    function test_can_claimAndTrade_using_0x_mainnet_fork_with_sellAmount_set() public {

        // TODO: figure out why rolling fork doesn't work, causes oracle.getLatestAnswer to revert without reason

        // move forward in time to accrue interest
        // emit log_named_uint("timestamp before", block.timestamp);
        // vm.rollFork(mainnetFork, finalBlockNumber);
        // emit log_named_uint("timestamp after", block.timestamp);

        vm.warp(block.timestamp + 24 hours);
        ( principal, interest) = line.updateOutstandingDebt();
        debtUSD = principal + interest;
        emit log_named_uint("debtUSD", debtUSD);

        // Claim revenue to the spigot
        spigot.claimRevenue(address(revenueContract), Denominations.ETH,  abi.encode(SimpleRevenueContract.sendPushPayment.selector));
        assertEq(address(spigot).balance, REVENUE_EARNED);

        // owner split should be 10% of claimed revenue
       ownerTokens = spigot.getOwnerTokens(Denominations.ETH);
        emit log_named_uint("ownerTokens ETH", ownerTokens);
        assertEq(ownerTokens, REVENUE_EARNED / ownerSplit);

        /*
            0x API call designating the sell amount:
            https://api.0x.org/swap/v1/quote?buyToken=DAI&sellToken=ETH&sellAmount=1500000000000000000
        */
        bytes memory tradeData = hex"3598d8ab0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000061512813302d7a66100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f46b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000005fb851ab9463a89b6e";

        vm.startPrank(arbiter);
        tokensBought = line.claimAndTrade(Denominations.ETH, tradeData);
        vm.stopPrank();
        
        ownerTokens = spigot.getOwnerTokens(Denominations.ETH);
        assertEq(ownerTokens, 0);
        assertEq(line.unused(DAI), tokensBought);

        (,uint principalTokens, uint256 interestAccruedTokens,,,,,) = line.credits(line.ids(0));

        numTokensToRepayDebt = principalTokens + interestAccruedTokens;
        emit log_named_uint("numTokensToRepayDebt", numTokensToRepayDebt);

        unusedTradedTokens = tokensBought - numTokensToRepayDebt;
        emit log_named_uint("unusedTradedTokens", unusedTradedTokens);

        vm.startPrank(borrower);
        line.useAndRepay(numTokensToRepayDebt);
        vm.stopPrank();

        uint256 unusedDai = line.unused(DAI);
        emit log_named_uint("unusedDai", unusedDai);
        

        (principal,interest) = line.updateOutstandingDebt();
        debtUSD = principal + interest;
        
        emit log_named_uint("principal", principal);
        emit log_named_uint("interest", interest);
        emit log_named_uint("debtUSD", debtUSD);

        uint256 borrowerDaiBalance = IERC20(DAI).balanceOf(borrower);
        vm.startPrank(borrower);
        line.close(line.ids(0));
        line.sweep(borrower, DAI);
        uint256 claimedEth = spigot.claimOperatorTokens(Denominations.ETH);
        vm.stopPrank();

        assertEq(IERC20(DAI).balanceOf(borrower), borrowerDaiBalance + unusedDai);
        assertEq(claimedEth, (REVENUE_EARNED / 100) * 90 );
    }


    function test_can_claimAndTrade_using_0x_with_buyAmount_set() public {

        // can't warp more than 24 hours or we get a stale price
        vm.warp(block.timestamp + 24 hours);
        (uint256 principal, uint256 interest) = line.updateOutstandingDebt();
        uint256 debtUSD = principal + interest;

        // Claim revenue to the spigot
        spigot.claimRevenue(address(revenueContract), Denominations.ETH,  abi.encode(SimpleRevenueContract.sendPushPayment.selector));
        assertEq(address(spigot).balance, REVENUE_EARNED);

        // owner split should be 10% of claimed revenue
        uint256 ownerTokens = spigot.getOwnerTokens(Denominations.ETH);
        assertEq(ownerTokens, REVENUE_EARNED / ownerSplit);


        // anyonemly send to the contract to see if it affects the trade
        deal(anyone, 25 ether);
        vm.prank(anyone);
        (bool sendSuccess, ) = payable(address(line)).call{value: 25 ether}("");
        assertTrue(sendSuccess);


        /*
            0x API call designating the buy amount:
            https://api.0x.org/swap/v1/quote?buyToken=DAI&sellToken=ETH&buyAmount=11000000000000000000000
        */
        bytes memory tradeData = hex"415565b0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000008007b220b072d2610000000000000000000000000000000000000000000002544faa778090e0000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000004c00000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000040000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000008007b220b072d261000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c00000000000000000000000000000000000000000000000008007b220b072d261000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000000008007b220b072d2610000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000000000000000000260ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000b446f646f563200000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000002544faa778090e00000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000400000000000000000000000003058ef90929cb8180174d74c507176cca6835d730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b5cc42ead263a8a7f9";

        vm.startPrank(arbiter);
        tokensBought = line.claimAndTrade(Denominations.ETH, tradeData);
        vm.stopPrank();
        ownerTokens = spigot.getOwnerTokens(Denominations.ETH);
        // emit log_named_uint("tokensBought", tokensBought);
        assertEq(ownerTokens, 0);
        assertEq(line.unused(DAI), tokensBought);

        (,uint principalTokens, uint256 interestAccruedTokens,,,,,) = line.credits(line.ids(0));

        numTokensToRepayDebt = principalTokens + interestAccruedTokens;
        // emit log_named_uint("numTokensToRepayDebt", numTokensToRepayDebt);

        unusedTradedTokens = tokensBought - numTokensToRepayDebt;
        // emit log_named_uint("unusedTradedTokens", unusedTradedTokens);

        uint256 lineDaiBalance = IERC20(DAI).balanceOf(address(line));
        uint256 unusedDai = line.unused(DAI);    

        // repay the full debt
        vm.startPrank(borrower);
        bool repaid = line.useAndRepay(numTokensToRepayDebt);
        assertTrue(repaid);
        vm.stopPrank();

        ( principal,  interest) = line.updateOutstandingDebt();
        assertEq(principal, 0);
        assertEq(interest, 0);

        // lender withdraws their deposit + interest earned
        ( deposit, , , interestRepaid,,, ,  ) = line.credits(line.ids(0));
        vm.startPrank(lender);
        line.withdraw(line.ids(0), deposit + interestRepaid); //10000.27
        vm.stopPrank();

        ( ,,,,,,,isOpen) = line.credits(line.ids(0));
        assertFalse(isOpen);


        // NOTE: withdrawing as the lender closes (deletes the line of credit, trapping any additional funds)

        unusedDai = line.unused(DAI);        
        uint256 unusedEth = line.unused(Denominations.ETH);
        lineDaiBalance = IERC20(DAI).balanceOf(address(line));

        // check the line's accounting
        assertEq(unusedDai, IERC20(DAI).balanceOf(address(line)), "unused dai should match the dai balance"); // the balance does not match because it hasn't been withdrawn
        assertEq(unusedEth, address(line).balance, "unused ETH should match the ETH balance");


         ( , , uint256 interestAccruedTokensAfter, ,,, ,  bool lineIsOpen) = line.credits(line.ids(0));
        // assertTrue(lineIsOpen);
        assertEq(interestAccruedTokensAfter, 0);


        LineLib.STATUS status = line.status();
        emit log_named_uint("status", uint256(status));
        assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID), "Line not repaid");

        uint256 borrowerDaiBalance = IERC20(DAI).balanceOf(borrower);
        uint256 borrowerEthBalance = borrower.balance;

        // borrower retrieve the remaining funds from the Line  
        vm.startPrank(borrower);        
        line.sweep(borrower, DAI);
        line.sweep(borrower, Denominations.ETH);
        vm.stopPrank();

        assertEq(IERC20(DAI).balanceOf(borrower), borrowerDaiBalance + unusedDai, "borrower DAI balance should have increased");
        assertEq(IERC20(DAI).balanceOf(address(line)), 0, "line's DAI balance should be 0");
        assertEq(borrower.balance, borrowerEthBalance + unusedEth, "borrower's ETH balance should increase");
        assertEq(address(line).balance, 0, "Line's ETH balance should be 0 after sweep");

        // TODO: why does this not revert?

        // The line was closed when lender withdrew, so expect a revert
        vm.startPrank(borrower);
        vm.expectRevert(ILineOfCredit.PositionIsClosed.selector);
        line.close(id);
        vm.stopPrank();

    }


    // /*////////////////////////////////////////////////
    // ////////////////    UTILS   //////////////////////
    // ////////////////////////////////////////////////*/


    function _setupSimulation() internal {

        ethPrice = oracle.getLatestAnswer(Denominations.ETH);
        daiPrice = oracle.getLatestAnswer(DAI);
        emit log_named_int("eth price", ethPrice);
        emit log_named_int("dai price", daiPrice);

        deal(DAI, lender, BORROW_AMOUNT_DAI);
        emit log_named_uint("lender dai balance", IERC20(DAI).balanceOf(lender));
        uint256 loanValueUSD = (IERC20(DAI).balanceOf(lender) * uint256(oracle.getLatestAnswer(DAI)))  / 10**18; // convert to 8 decimals
        emit log_named_uint("DAI loan value in USD", loanValueUSD);

        // Create the position
        vm.startPrank(borrower);
        line.addCredit(dRate, fRate, BORROW_AMOUNT_DAI, DAI, lender);
        vm.stopPrank();
        
        startHoax(lender);
        IERC20(DAI).approve(address(line), BORROW_AMOUNT_DAI);
        id = line.addCredit(dRate, fRate, BORROW_AMOUNT_DAI, DAI, lender);
        emit log_named_bytes32("position id", id);
        vm.stopPrank();

        assertEq(IERC20(DAI).balanceOf(address(line)), BORROW_AMOUNT_DAI);
        assertEq(IERC20(DAI).balanceOf(lender), 0);

        // borrow
        vm.startPrank(borrower);
        line.borrow(line.ids(0), BORROW_AMOUNT_DAI);
        vm.stopPrank();

        assertEq(IERC20(DAI).balanceOf(address(line)), 0);
        assertEq(IERC20(DAI).balanceOf(borrower), BORROW_AMOUNT_DAI);

        // Simulate ETH revenue generation
        deal(address(revenueContract), REVENUE_EARNED);

    }


}