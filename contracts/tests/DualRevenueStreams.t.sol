pragma solidity 0.8.16;

import "forge-std/Test.sol";

import { Denominations } from "chainlink/Denominations.sol";
import { Oracle } from "../modules/oracle/Oracle.sol";
import { Spigot } from "../modules/spigot/Spigot.sol";
import { Escrow } from "../modules/escrow/Escrow.sol";
import { SecuredLine } from "../modules/credit/SecuredLine.sol";
import { ILineOfCredit } from "../interfaces/ILineOfCredit.sol";
import { ISecuredLine } from "../interfaces/ISecuredLine.sol";
import { IEscrow } from "../interfaces/IEscrow.sol";
import { ISpigot } from "../interfaces/ISpigot.sol";

import {LineFactory} from "../modules/factories/LineFactory.sol";
import {ModuleFactory} from "../modules/factories/ModuleFactory.sol";
import {ILineFactory} from "../interfaces/ILineFactory.sol";

import { LineLib } from "../utils/LineLib.sol";
import { MutualConsent } from "../utils/MutualConsent.sol";
import { ZeroEx } from "../mock/ZeroEx.sol";
import {MockRegistry} from "../mock/MockRegistry.sol";
import {SimpleRevenueContract} from "../mock/SimpleRevenueContract.sol";
import { MockLine } from "../mock/MockLine.sol";
import { SimpleOracle } from "../mock/SimpleOracle.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";


contract DualRevenueStreamsTest is Test {

    IEscrow escrow;
    ISpigot spigot;
    SecuredLine line;
    LineFactory lineFactory;
    ModuleFactory moduleFactory;
    SimpleRevenueContract pullRevenueContract;
    MockRegistry mockRegistry;
    Oracle oracle;
    ZeroEx dex;

    uint128 dRate = 1000;
    uint128 fRate = 1000;
    uint256 ttl = 2592000;
    uint8 revenueSplit = 90;

    address borrower;
    address arbiter;
    address lender;
    address lineAddress;

    uint256 mainnetFork;

    uint256 constant LOAN_AMT = 100_000 ether;
    uint256 constant MAX_INT = type(uint256).max;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant SNX = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address constant TETHER = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant ZERO_EX = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address constant ORACLE = 0x9EAb5422288805b59391D1442e29Fa16a04A0B22;

    address constant PUSH_REVENUE_EOA = 0x9832FD4537F3143b5C2989734b11A54D4E85eEF6;
    address constant THOMAS = 0x0325C59BA55F6705C2AC6213628222Cf193d423D;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    // prevent stack-too-deep
    uint256 principal;
    uint256 interest;
    uint256 interestRepaid;
    uint256 claimed;
    uint256 spigotOwnerTokens;
    uint256 spigotOperatorTokens;
    uint256 expectedOwnerTokens;
    uint256 expectedOperatorTokens;
    uint256 preClaimSpigotOperatorTokens;
    uint256 preClaimSpigotOwnerTokens;

    constructor () {} 

    function setUp() public {

        mainnetFork = vm.createFork(MAINNET_RPC_URL, 16_599_544); // 1 block before actual TXs begin
        vm.selectFork(mainnetFork);

        borrower = makeAddr("borrower"); 
        lender = address(10);
        arbiter = address(this);

        dex = new ZeroEx();

        deal(DAI, address(dex), MAX_INT / 2);
        deal(USDC, address(dex), MAX_INT / 2);
        deal(TUSD, address(dex), MAX_INT / 2);
        
        pullRevenueContract = new SimpleRevenueContract(borrower, USDC);

        // create our own oracle as we can't simulate Ox call data for dynamic swaps
        mockRegistry = new MockRegistry();
        mockRegistry.addToken(DAI, 10);
        mockRegistry.addToken(USDC, 10);
        mockRegistry.addToken(TUSD, 10);

        oracle = new Oracle(address(mockRegistry));

        // factories
        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(
            address(moduleFactory),
            arbiter,
            address(oracle),
            payable(address(dex))
            // payable(ZERO_EX)
        );

        // setup the line
        ILineFactory.CoreLineParams memory coreParams = ILineFactory
            .CoreLineParams({
                borrower: borrower,
                ttl: ttl,
                cratio: 1000,
                revenueSplit: 90
            });
    
        vm.startPrank(borrower);
        lineAddress = lineFactory.deploySecuredLineWithConfig(coreParams);
        vm.stopPrank();

        line = SecuredLine(payable(lineAddress));
        escrow = line.escrow();
        spigot = line.spigot();

        // enable collateral
        escrow.enableCollateral(TUSD);

        // add a revenue PUSH stream
        ISpigot.Setting memory settingsPush = ISpigot.Setting({
            ownerSplit: revenueSplit, // 90
            claimFunction: bytes4(0),
            transferOwnerFunction: bytes4("1234")
        });

        line.addSpigot(PUSH_REVENUE_EOA, settingsPush);

        // add a revenue PULL stream
        ISpigot.Setting memory settingsPull = ISpigot.Setting({
            ownerSplit: revenueSplit, // 90
            claimFunction: SimpleRevenueContract.claimPullPayment.selector,
            transferOwnerFunction: bytes4("1234")
        });

        line.addSpigot(address(pullRevenueContract), settingsPull);

        // make the spigot the owner of the revenue contract
        vm.prank(borrower);
        pullRevenueContract.transferOwnership(address(spigot));

        // // whitelist the claimRevenue function on behalf of the borrower, ie as arbiter
        // line.updateWhitelist(SimpleRevenueContract.claimPullPayment.selector, true);

        deal(TUSD, borrower, LOAN_AMT / 3);
        deal(DAI, lender, LOAN_AMT);
        deal(USDC, address(this), MAX_INT / 2);
        deal(USDC, PUSH_REVENUE_EOA, MAX_INT / 2);

        // approve tokens, add collateral, and propose position
        vm.startPrank(borrower);
        IERC20(TUSD).approve(address(escrow), MAX_INT);

        escrow.addCollateral( LOAN_AMT / 3, TUSD);

        // propose position
        line.addCredit(
            dRate,
            fRate,
            LOAN_AMT,
            DAI,
            lender
        );
        vm.stopPrank();

        // accept position
        vm.startPrank(lender);
        IERC20(DAI).approve(lineAddress, MAX_INT);
        line.addCredit(
            dRate,
            fRate,
            LOAN_AMT,
            DAI,
            lender
        );
        vm.stopPrank();
    }

    function test_can_add_push_and_pull_revenue_streams() public {
        bytes32 lineId = line.ids(0);

        // _rollAndWarpToBlock(block.number + advanceBlocks); // borrow block
        vm.startPrank(borrower);
        line.borrow(lineId, LOAN_AMT);
        vm.stopPrank();

        _rollAndWarpToBlock(block.number + 50_000);

        // generate revenue for pull
        IERC20(USDC).transfer(address(pullRevenueContract), 500e6);
        
        // revenue for push
        vm.prank(PUSH_REVENUE_EOA);
        IERC20(USDC).transfer(address(spigot), 500e6);

        // claim revenues
        vm.startPrank(borrower);
        emit log_string("=> claiming PUSH revenue");
        claimed = spigot.claimRevenue(PUSH_REVENUE_EOA, USDC, bytes(""));
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("[$USDC] owner tokens after PUSH claimeRevenue", spigotOwnerTokens);
        emit log_named_uint("[$USDC] operator tokens after PUSH claimeRevenue", spigotOperatorTokens);
        emit log_named_uint("[$USDC] line balance after PUSH claimeRevenue", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("[$USDC] spigot balance after PUSH claimeRevenue", IERC20(USDC).balanceOf(address(spigot)));

        emit log_string("=> claiming PULL revenue");
        bytes memory pullClaimData = abi.encodeWithSelector(SimpleRevenueContract.claimPullPayment.selector);
        claimed = spigot.claimRevenue(address(pullRevenueContract), USDC, pullClaimData);
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("[$USDC] owner tokens after PULL claimeRevenue", spigotOwnerTokens);
        emit log_named_uint("[$USDC] operator tokens after PULL claimeRevenue", spigotOperatorTokens);
        emit log_named_uint("[$USDC] line balance after PULL claimeRevenue", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("[$USDC] spigot balance after PULL claimeRevenue", IERC20(USDC).balanceOf(address(spigot)));
        vm.stopPrank();

        // more revenue for push
        vm.prank(PUSH_REVENUE_EOA);
        IERC20(USDC).transfer(address(spigot), 750e6);

        vm.startPrank(borrower);
        emit log_string("=> claiming PUSH revenue");
        claimed = spigot.claimRevenue(PUSH_REVENUE_EOA, USDC, bytes(""));
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("[$USDC] owner tokens after PUSH claimeRevenue", spigotOwnerTokens);
        emit log_named_uint("[$USDC] operator tokens after PUSH claimeRevenue", spigotOperatorTokens);
        emit log_named_uint("[$USDC] line balance after PUSH claimeRevenue", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("[$USDC] spigot balance after PUSH claimeRevenue", IERC20(USDC).balanceOf(address(spigot)));
        vm.stopPrank();

        // check accounting
        line.accrueInterest();
        (, principal, interest, interestRepaid,,,,) = line.credits(line.ids(0));
        emit log_named_uint("principal pre payment", principal);
        emit log_named_uint("interest pre payment", interest);

        // claimAndRepay ( as arbiter )
        bytes memory repayData = abi.encodeWithSignature(
            'trade(address,address,uint256,uint256)',
            USDC,
            DAI,
            spigotOwnerTokens, // note: should be 1:1
            spigotOwnerTokens * 10**12 // convert to DAI
        );
        line.claimAndRepay(USDC, repayData);

        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);

        assertEq(IERC20(USDC).balanceOf(address(spigot)), spigotOperatorTokens, "spigot operator token mismatch");
        assertEq(IERC20(USDC).balanceOf(lineAddress), 0, "Non-Zero line balance");

        (, principal, interest, interestRepaid,,,,) = line.credits(line.ids(0));
        emit log_named_uint("principal post payment", principal);
        emit log_named_uint("interest post payment", interest);
        emit log_named_uint("interestRepaid post payment", interestRepaid);
        emit log_named_uint("[$USDC] owner tokens after PUSH claimeRevenue", spigotOwnerTokens);
        emit log_named_uint("[$USDC] operator tokens after PUSH claimeRevenue", spigotOperatorTokens);
        emit log_named_uint("[$USDC] line balance after PUSH claimeRevenue", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("[$USDC] spigot balance after PUSH claimeRevenue", IERC20(USDC).balanceOf(address(spigot)));

    }

    function test_can_repay_position_using_push_and_pull_revenue(uint256 advanceBlocks, uint256 borrowAmount, uint256 repayment)  public {
        vm.assume(borrowAmount > 0);
        vm.assume(advanceBlocks > 0);
        vm.assume(repayment > 0 && repayment % 2 == 0);
        borrowAmount = bound(borrowAmount, 10 ether, LOAN_AMT);
        advanceBlocks = bound(advanceBlocks, 100, 10_000);
        repayment = bound(repayment, 500e6, 2250e6); // USDC, ie 6 decimals
        
        bytes32 lineId = line.ids(0);

        // _rollAndWarpToBlock(block.number + advanceBlocks); // borrow block
        vm.startPrank(borrower);
        line.borrow(lineId, borrowAmount);
        vm.stopPrank();
        

        line.accrueInterest();

        uint256 iterations;

        while (principal > 0 || interest > 0) {
            emit log_named_uint("iteration", ++iterations);

            _rollAndWarpToBlock(block.number + advanceBlocks);

            // generate revenue for pull
            IERC20(USDC).transfer(address(pullRevenueContract), repayment);
        
            // revenue for push
            vm.prank(PUSH_REVENUE_EOA);
            IERC20(USDC).transfer(address(spigot), repayment / 2);

            // claim revenues
            vm.startPrank(borrower);
            emit log_string("=> claiming PUSH revenue");
            preClaimSpigotOperatorTokens = spigot.getOperatorTokens(USDC);
            claimed = spigot.claimRevenue(PUSH_REVENUE_EOA, USDC, bytes(""));
            spigotOwnerTokens = spigot.getOwnerTokens(USDC);
            spigotOperatorTokens = spigot.getOperatorTokens(USDC);
            expectedOwnerTokens = (claimed * revenueSplit) / 100;
            expectedOperatorTokens = preClaimSpigotOperatorTokens + (claimed * (100-revenueSplit)) / 100;
            assertEq(spigotOwnerTokens, expectedOwnerTokens, "owner tokens dont match");
            assertEq(expectedOperatorTokens, spigotOperatorTokens, "operator tokens dont match");
            assertEq(spigotOperatorTokens, claimed - expectedOwnerTokens + preClaimSpigotOperatorTokens, "token totals don't add up");

            emit log_string("=> claiming PULL revenue");
            preClaimSpigotOperatorTokens = spigotOperatorTokens;
            preClaimSpigotOwnerTokens = spigotOwnerTokens;
            bytes memory pullClaimData = abi.encodeWithSelector(SimpleRevenueContract.claimPullPayment.selector);
            claimed = spigot.claimRevenue(address(pullRevenueContract), USDC, pullClaimData);
            spigotOwnerTokens = spigot.getOwnerTokens(USDC);
            spigotOperatorTokens = spigot.getOperatorTokens(USDC);
            spigotOperatorTokens = spigot.getOperatorTokens(USDC);
            expectedOwnerTokens = (claimed * revenueSplit) / 100;
            assertEq(spigotOwnerTokens, preClaimSpigotOwnerTokens + expectedOwnerTokens, "expected owner tokens don't match");
            assertEq(spigotOperatorTokens, claimed - expectedOwnerTokens + preClaimSpigotOperatorTokens, "token totals don't match");
            vm.stopPrank();

            // check accounting
            line.accrueInterest();
            (, principal, interest, interestRepaid,,,,) = line.credits(line.ids(0));
            emit log_named_uint("principal pre payment", principal);
            emit log_named_uint("interest pre payment", interest);

            // claimAndRepay ( as arbiter )
            bytes memory repayData = abi.encodeWithSignature(
                'trade(address,address,uint256,uint256)',
                USDC,
                DAI,
                spigotOwnerTokens, // note: should be 1:1
                spigotOwnerTokens * 10**12 // convert to DAI decimals
            );
            line.claimAndRepay(USDC, repayData);

            spigotOwnerTokens = spigot.getOwnerTokens(USDC);
            spigotOperatorTokens = spigot.getOperatorTokens(USDC);

            assertEq(spigotOwnerTokens, 0, "non-zero owner tokens");

            assertEq(IERC20(USDC).balanceOf(address(spigot)), spigotOperatorTokens, "spigot operator token mismatch");
            assertEq(IERC20(USDC).balanceOf(lineAddress), 0, "Non-Zero line balance");

            (, principal, interest, interestRepaid,,,,) = line.credits(line.ids(0));
        }
        emit log_named_uint("iterations", iterations);
        assertEq(principal, 0, "principal is non-zero");
        assertEq(interest, 0, "interest is non-zero");

    }

    function _rollAndWarpToBlock(uint256 rollToBlock) internal {
        emit log_string("=======================");
        uint256 currentBlock = block.number;
        assertTrue(currentBlock < rollToBlock, "Can only roll forward in time");

        uint256 diff = rollToBlock - currentBlock;
        uint256 warpTime = diff/12;
        vm.roll(rollToBlock);
        emit log_named_uint("@ @ @ Rolling to block", rollToBlock);
        vm.warp(block.timestamp + warpTime);
    }
}