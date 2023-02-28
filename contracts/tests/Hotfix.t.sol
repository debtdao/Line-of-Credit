pragma solidity 0.8.16;

import "forge-std/Test.sol";
import { Denominations } from "chainlink/Denominations.sol";

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

import { MockLine } from "../mock/MockLine.sol";
import { SimpleOracle } from "../mock/SimpleOracle.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

contract HotfixTest is Test {

    IEscrow escrow;
    ISpigot spigot;
    SecuredLine line;
    LineFactory lineFactory;
    ModuleFactory moduleFactory;

    uint MAX_INT = type(uint256).max;
    uint128 dRate = 1000;
    uint128 fRate = 1000;
    uint ttl = 2592000;
    uint8 revenueSplit = 90;

    address borrower;
    address arbiter;
    address lender;
    address lineAddress;

    uint256 mainnetFork;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant SNX = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address constant ZERO_EX = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address constant ORACLE = 0x9EAb5422288805b59391D1442e29Fa16a04A0B22;

    address constant BORROWER_REVENUE_EOA = 0x9832FD4537F3143b5C2989734b11A54D4E85eEF6;
    address constant THOMAS = 0x0325C59BA55F6705C2AC6213628222Cf193d423D;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    constructor(){}

    function setUp() external {
        mainnetFork = vm.createFork(MAINNET_RPC_URL, 16_599_544); // 1 block before actual TXs begin
        vm.selectFork(mainnetFork);

        borrower = 0xf44B95991CaDD73ed769454A03b3820997f00873; 
        lender = address(10);
        arbiter = address(this);

        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(
            address(moduleFactory),
            arbiter,
            ORACLE,
            payable(ZERO_EX)
        );

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

        _mintAndApprove();

    }

    function _mintAndApprove() internal {

        // enable collateral
        escrow.enableCollateral(SNX);

        // add a revenue stream
        ISpigot.Setting memory setting = ISpigot.Setting({
            ownerSplit: revenueSplit, // 90
            claimFunction: bytes4(0),
            transferOwnerFunction: bytes4("1234")
        });

        line.addSpigot(BORROWER_REVENUE_EOA, setting);

        // ensure balances are sufficient
        deal(DAI, lender, 1000 ether);
        deal(USDC, borrower, 100e6);
        deal(USDC, BORROWER_REVENUE_EOA, 100e6);

        emit log_named_uint("Mo SNX balance", IERC20(SNX).balanceOf(borrower));
        emit log_named_uint("Mo DAI balance", IERC20(DAI).balanceOf(borrower));
        emit log_named_uint("Mo USDC balance", IERC20(USDC).balanceOf(borrower));

        // approve tokens, add collateral, and propose position
        vm.startPrank(borrower);
        IERC20(SNX).approve(address(escrow), MAX_INT);

        escrow.addCollateral(3.3 ether, SNX);

        line.addCredit(
            dRate,
            fRate,
            50000000000000000000,
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
            50000000000000000000,
            DAI,
            lender
        );
        vm.stopPrank();

    }

    // @note: This test replicates an accounting bug discovered in _claimRevenue in the SpigotLib
    // contract that didn't take into account the operatorToken balance when claiming revenue
    // @note: mainnet contract: 0x6e3a81f41210d45a2bbbbad00f25fd96567b9af2
    function test_accounting_for_multiple_claim_revenue_invocations() external {
        bytes32 lineId = line.ids(0);

        // borrow 10 DAI
        _rollAndWarpToBlock(16_600_785); // borrow block
        emit log_string("=> Borrowing");
        vm.startPrank(borrower);
        line.borrow(lineId, 10 ether);
        vm.stopPrank();

        // 16_678_623: transfer 15 USDC to spigot
        _rollAndWarpToBlock(16_678_623); 
        vm.startPrank(BORROWER_REVENUE_EOA);
        emit log_string("=> Transferring revenue to spigot");
        IERC20(USDC).transfer(address(spigot), 15e6);
        assertEq(IERC20(USDC).balanceOf(address(spigot)), 15e6);
        uint256 spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        uint256 spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("owner tokens USDC after useAndRepay", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after useAndRepay", spigotOperatorTokens);
        emit log_named_uint("line USDC balance", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance", IERC20(USDC).balanceOf(address(spigot)));
        vm.stopPrank();

        // 16_678_635: borrower calls claim revenue
        _rollAndWarpToBlock(16_678_635); 
        vm.startPrank(borrower);
        emit log_string("=> claimRevenue()");
        uint256 claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("owner tokens USDC", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC", spigotOperatorTokens);
        uint256 expectedOwnerTokens = (claimed * revenueSplit) / 100;
        assertEq(spigotOwnerTokens, expectedOwnerTokens);
        assertEq(spigotOperatorTokens, claimed - expectedOwnerTokens);
        vm.stopPrank();

        // 16_685_641: arbiter calls claimAndTrade ( 13500000 in)
        _rollAndWarpToBlock(16_685_641); 
        vm.startPrank(arbiter);
        emit log_string("=> claimAndTrade()");
        line.claimAndTrade(USDC,hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000cdfe60000000000000000000000000000000000000000000000000b9c4f4da1409985600000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd000000000000000000000000e9039a6968ed998139e023ed8d41c7fa77b7ff7a0000000000000000000000000000000000000000000000cb3b1dde6d63f65891");
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("owner tokens USDC after claimAndTrade", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after claimAndTrade", spigotOperatorTokens);
        vm.stopPrank();

        // 16_685_974: borrower calls useAndRepay
        _rollAndWarpToBlock(16_685_974); 
        (, uint256 principal,uint256 interest,,,,,) = line.credits(line.ids(0));
        emit log_named_uint("principal", principal);
        emit log_named_uint("interest", interest);
        
        vm.startPrank(borrower);
        emit log_string("=> useAndRepay()");
        line.useAndRepay(10 ether);
        vm.stopPrank();

        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        assertEq(IERC20(USDC).balanceOf(address(spigot)), spigotOperatorTokens);
        emit log_named_uint("owner tokens USDC after useAndRepay", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after useAndRepay", spigotOperatorTokens);
        emit log_named_uint("line USDC balance", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance", IERC20(USDC).balanceOf(address(spigot)));

        // full 15 USDC has been used at this point
        /// note: 1.5 USDC remains in operator tokens

/*
        // 16_687_230: claimRevenue (called by thomas)
        _rollAndWarpToBlock(16_687_230); 
        vm.startPrank(THOMAS);
        emit log_string("=> claimRevenue()");
        vm.expectRevert(ISpigot.NoRevenue.selector);
        claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        expectedOwnerTokens = (claimed * revenueSplit) / 100;
        assertEq(spigotOwnerTokens, expectedOwnerTokens);
        assertEq(spigotOperatorTokens, claimed - expectedOwnerTokens);
        emit log_named_uint("owner tokens USDC after thomas claim Revenue", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after  thomas claim Revenue", spigotOperatorTokens);
        emit log_named_uint("line USDC balance after  thomas claim Revenue", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance after  thomas claim Revenue", IERC20(USDC).balanceOf(address(spigot)));
        vm.stopPrank();

        // 16_687_712: claimAndRepay
        _rollAndWarpToBlock(16_687_712); 
        emit log_string("=> claimAndRepay()");
        line.claimAndRepay(USDC,hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000149970000000000000000000000000000000000000000000000000128e269a9e9abf4100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd000000000000000000000000e9039a6968ed998139e023ed8d41c7fa77b7ff7a0000000000000000000000000000000000000000000000b9a844386663f6ab7a");
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("owner tokens USDC after claimAndRepay", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after claimAndRepay", spigotOperatorTokens);
        emit log_named_uint("line USDC balance after claimAndRepay", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance after claimAndRepay", IERC20(USDC).balanceOf(address(spigot)));

        // 16_692_741: transfer 15 USDC to spigot
        _rollAndWarpToBlock(16_692_741); 
        vm.startPrank(BORROWER_REVENUE_EOA);
        emit log_string("=> Transferring revenue to spigot");
        IERC20(USDC).transfer(address(spigot), 15e6);
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("owner tokens USDC after transfer", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after transfer", spigotOperatorTokens);
        emit log_named_uint("line USDC balance", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance", IERC20(USDC).balanceOf(address(spigot)));
        vm.stopPrank();

        // 16_693_128: claimRevenue
        _rollAndWarpToBlock(16_693_128); 
        vm.startPrank(borrower);
        emit log_string("=> claimRevenue()");
        claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        expectedOwnerTokens = (claimed * revenueSplit) / 100;
        assertEq(spigotOwnerTokens, expectedOwnerTokens);
        assertEq(spigotOperatorTokens, claimed - expectedOwnerTokens);
        emit log_named_uint("owner tokens USDC after claimRevenue", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after claimRevenue", spigotOperatorTokens);
        emit log_named_uint("line USDC balance", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance", IERC20(USDC).balanceOf(address(spigot)));
        vm.stopPrank();

        // 16_694_077: claimRevenue
        _rollAndWarpToBlock(16_694_077); 
        vm.startPrank(borrower);
        emit log_string("=> claimRevenue()");
        claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        expectedOwnerTokens = (claimed * revenueSplit) / 100;
        assertEq(spigotOwnerTokens, expectedOwnerTokens);
        assertEq(spigotOperatorTokens, claimed - expectedOwnerTokens);
        emit log_named_uint("owner tokens USDC after claimRevenue", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after claimRevenue", spigotOperatorTokens);
        emit log_named_uint("line USDC balance", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance", IERC20(USDC).balanceOf(address(spigot)));
        vm.stopPrank();

        // 16_694_108: claimAndRepay
        _rollAndWarpToBlock(16_694_108); 
        emit log_string("=> claimAndRepay()");
        line.claimAndRepay(USDC,hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000149970000000000000000000000000000000000000000000000000128e269a9e9abf4100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd000000000000000000000000e9039a6968ed998139e023ed8d41c7fa77b7ff7a0000000000000000000000000000000000000000000000b9a844386663f6ab7a");
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("owner tokens USDC after claimAndRepay", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after claimAndRepay", spigotOperatorTokens);
        emit log_named_uint("line USDC balance after claimAndRepay", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance after claimAndRepay", IERC20(USDC).balanceOf(address(spigot)));


        // 16_701_533: transfer 3 USDC to spigot
        _rollAndWarpToBlock(16_701_533); 
        vm.startPrank(BORROWER_REVENUE_EOA);
        emit log_string("=> Transferring revenue to spigot");
        IERC20(USDC).transfer(address(spigot), 3e6);
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("owner tokens USDC after transfer", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after transfer", spigotOperatorTokens);
        emit log_named_uint("line USDC balance", IERC20(USDC).balanceOf(lineAddress));
        emit log_named_uint("spigot USDC balance", IERC20(USDC).balanceOf(address(spigot)));
        vm.stopPrank();

        */
        
    }

    //    

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