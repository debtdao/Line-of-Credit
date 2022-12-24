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
    uint256 constant REVENUE_EARNED = 10 ether;

    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf; // Chainlink
    address constant swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // 0x
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Line access control vars
    address private arbiter = makeAddr("arbiter");
    address private borrower = makeAddr("borrower");
    address private lender = makeAddr("lender");
    address private testaddr = makeAddr("test");
    

    uint256 constant initialBlockNumber = 16_082_690; // Nov-30-2022 12:05:23 PM +UTC
    uint256 constant finalBlockNumber = 16_155_490; // Dec-24-2022 03:28:23 PM +UTC

    uint256 constant BORROW_AMOUNT_DAI = 10_000 * 10**18; // $10k USD

    int256 ethPrice;
    int256 daiPrice;


    /**
        In this scenario, a borrower borrows ~$10k worth of DAI (10k DAI).
        Interest is accrued over 30 days.
        Revenue of 15 Eth is claimed from the revenue contract.
        10% (1.5 Eth) is stored in spigot as owner tokens.
        90% (13.5 Eth) is stored in spigot as operator tokens, then claimed.
        1.5 Eth is claimed from the Spigot and traded for DAI.
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

    function test_claiming_and_trading_using_0x_mainnet_fork() public {

        // TODO: figure out why rolling fork doesn't work, causes oracle.getLatestAnswer to revert without reason

        // // move forward in time to accrue interest
        // emit log_named_uint("timestamp before", block.timestamp);
        // vm.rollFork(mainnetFork, finalBlockNumber);
        // emit log_named_uint("timestamp after", block.timestamp);

        // assertEq(block.number, finalBlockNumber);
        // ethPrice = oracle.getLatestAnswer(Denominations.ETH);
        // daiPrice = oracle.getLatestAnswer(DAI);
        // emit log_named_int("eth price", ethPrice);
        // emit log_named_int("dai price", daiPrice);

        vm.warp(30 days);
        (uint256 principal, uint256 interest) = line.updateOutstandingDebt();
        emit log_named_uint("principal", principal);
        emit log_named_uint("interest", interest);
        uint256 owed = principal + interest;


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
        bytes32 id = line.addCredit(dRate, fRate, BORROW_AMOUNT_DAI, DAI, lender);
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

    }


}