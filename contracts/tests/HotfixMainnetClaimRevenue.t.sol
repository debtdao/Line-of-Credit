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

    /*
    *   @note:      A bug was introduced following changes that were made based on issues discovered
    *               in the Code4rena audit. It became necessary to have the Operator claim tokens in a 
    *               separate tx, as opposed to being part of the claimRevenue call.  This resulted in
    *               an excess of tokens that were not accounted for in the claimRevenue function's logic.
    *               As a result, it was possible to claim more tokens as revenue than should've been available
    *               , but only in scenarios where push payments were used, and incorrectly increasing 
    *               state.operatorTokens by the amount that was now unaccounted for.
    *   @link:      https://debtdao.notion.site/Spigot-Claim-Revenue-Accounting-01153e95f1be47d194ec9f252304855b
    *   @dev:       This test file tests against a fork of mainnet and evaluates the actual function calls for correctness.
    *   @dev:       The block number of, and a link to, each transaction is included in the comments above each step
    *               in the sequence, ie. test fn.
    *   @dev:       The tests intentionally make use of the incorrect math that's present in the contract.  The assertions 
    *               for the corrected contracts are included in the tests, but left commented-out.
    *   @dev:       Original Spigot: 0x6E3a81f41210D45A2bBBBad00f25Fd96567b9af2
    *   @dev:       Original Escrow: 0x46898c8c8082c4d67f8d45d24859a92beef86306
    *   @dev:       Original Line Of Credit: 0x5bda5b7a953f71f03711f9c0bd2c10c1738f6ee4
    */

contract HotfixMainnetClaimRevenueTest is Test {

    IEscrow escrow;
    ISpigot spigot;
    SecuredLine line;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant SNX = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address constant ZERO_EX = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address constant ORACLE = 0x9EAb5422288805b59391D1442e29Fa16a04A0B22;

    address constant ARBITER = address(0xE9039a6968ED998139e023ed8D41c7fA77B7fF7A);
    address constant BORROWER = 0xf44B95991CaDD73ed769454A03b3820997f00873; 
    address constant BORROWER_REVENUE_EOA = 0x9832FD4537F3143b5C2989734b11A54D4E85eEF6;
    address constant THOMAS = 0x0325C59BA55F6705C2AC6213628222Cf193d423D;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint8 revenueSplit = 90;

    // res-usable
    uint256 spigotOwnerTokens;
    uint256 spigotOperatorTokens;

    function setUp() public {
        escrow = IEscrow(0x46898c8c8082C4d67F8D45d24859a92beeF86306);
        spigot = ISpigot(0x6E3a81f41210D45A2bBBBad00f25Fd96567b9af2);
        line = SecuredLine(payable(0x5Bda5b7a953f71f03711f9C0Bd2c10C1738f6ee4));
    }

    // This test should pass as expected as on the first claimRevenue call, there's no underlying token
    // balances to upset the accounting.
    // 16_678_635: borrower calls claim revenue
    // https://etherscan.io/tx/0x13e22f6e3e98318dd43fb7f60ec9c09450aab48e094b76e78a5b2bd7da656b4d
    function test_mainnet_borrower_claims_revenue_for_the_first_time() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_678_635-1);

        vm.startPrank(BORROWER);
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
    }

    // during claimAndTrade, the owner tokens (USDC) are claimed from the spigot and traded for DAI, the
    // accounting issues do not arise yet because claimRevenue has only been called once
    // 16_685_641: arbiter calls claimAndTrade ( 13500000 USDC is claimed from the spigot)
    // https://etherscan.io/tx/0x0e3b431826afe6dfcbefff9e50e21188abc8a84fcc14b5adcce83930540fbeed
    function test_mainnet_borrower_calls_claimAndTrade_succeeds() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_678_635);

        vm.startPrank(ARBITER);
        emit log_string("=> claimAndTrade()");
        // 0x trade data for 13500000 USDC
        uint256 spigotUsdcBalanceBefore = IERC20(USDC).balanceOf(address(spigot));
        uint256 unusedDai = line.claimAndTrade(USDC,hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000cdfe60000000000000000000000000000000000000000000000000b9c4f4da1409985600000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd000000000000000000000000e9039a6968ed998139e023ed8d41c7fa77b7ff7a0000000000000000000000000000000000000000000000cb3b1dde6d63f65891");
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        assertEq(spigotOwnerTokens, 0);
        assertEq(unusedDai, line.unused(DAI));
        assertEq(spigotOperatorTokens, spigotUsdcBalanceBefore - 13_500_000);
        vm.stopPrank();
    }

    // The borrower calls use and repay to use the unusedTokens in the Line Of Credit to repay 
    // the accrued interest and/or principal. We don't expect any spigot values to change in this tx,
    // we simply include it to keep the sequence of transactions consistent.
    // 16_685_974: borrower calls useAndRepay
    // https://etherscan.io/tx/0xcbcc1d7674f053369d92dc830e9a05d08bbf51a3a76b9c153f3dffcde273e1bd
    function test_mainnet_useAndRepay_succeeds() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_685_974-1);
        vm.startPrank(BORROWER);
        line.useAndRepay(10 ether);
        vm.stopPrank();

        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        assertEq(IERC20(USDC).balanceOf(address(spigot)), spigotOperatorTokens);

        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("owner tokens USDC after useAndRepay", spigotOwnerTokens);
        emit log_named_uint("operator tokens USDC after useAndRepay", spigotOperatorTokens);
    }


    // note:    This is the tx where the bug first rears its head.  The spigot's balance is $USDC 1.5, which should
    //          fall under the accounting of the operatorTokens ( 10% of 15 $USDC revenue), but is not. When claimRevenue
    //          is called again, this qty is then assumed to be revenue and the accounting adjusts accordingly.
    // 16_687_230: claimRevenue (called by thomas)
    // https://etherscan.io/tx/0x41d7f72a30dc64a55b20cd255e2fdfedda625ba2fa7129bb99ab0c2305844a05
    function test_mainnet_claimRevenue_second_call() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_687_230-1);
        vm.startPrank(THOMAS);

        assertEq(1_500_000, IERC20(USDC).balanceOf(address(spigot)), "spigot balance incorrect");

        uint256 spigotOwnerTokensBefore = spigot.getOwnerTokens(USDC); 
        assertEq(0, spigotOwnerTokensBefore, "owner tokens should be 0");
      
        uint256 spigotOperatorTokensBefore = spigot.getOperatorTokens(USDC);
        assertEq(1_500_000, spigotOperatorTokensBefore, "operator tokens should be 1_500_000");

        // without the bug, this would revert as there should be no revenue, but instead the $USDC 1.5 is claimed as revenue
        // instead of being recorded as operator tokens and zeroed out.
        uint256 claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));
        assertEq(claimed, 1_500_000, "incorrect claim amount"); // incorrectly claimed tokens

        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);

        uint256 expectedOwnerTokens = (claimed * revenueSplit) / 100;
        assertEq(expectedOwnerTokens, spigotOwnerTokens, "expected owner token balance does not match actual owner token balance");

        // note: in the bug-free contracts, the operator token balance would not increase because
        // there would be no revenue to claim. ie, uint256 expectedOperatorTokens = (claimed * (100 - revenueSplit) / 100);

        // with the presence of the bug, the original operator balance increases by 10% (the operator's split)
        // because the 1_500_000 balance of the spigot is incorrectly "claimed" as revenue
        uint256 expectedOperatorTokens = spigotOperatorTokensBefore + (claimed * (100 - revenueSplit) / 100);

        assertEq(expectedOperatorTokens, spigotOperatorTokens, "expected operator token balance does not match actual owner token balance");
        vm.stopPrank();
    }

    // note:    This call to `claimAndRepay` should revert as there should be no revenue to claim, however
    //          the TX succeeds as the contract believes the unaccounted for operatorTokens are revenue.
    // 16_687_712: arbiter calls claimAndRepay
    // https://etherscan.io/tx/0x6a16a8a0638c7ab266988a9a77befbd70e104289b8bdbdcaacd614edc1abb87c  
    function test_mainnet_claimAndRepay_after_claiming_revenue() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_687_712-1);

        vm.startPrank(ARBITER);
        uint256 balanceBefore = IERC20(USDC).balanceOf(address(spigot));
        uint256 spigotOwnerTokensBefore = spigot.getOwnerTokens(USDC); 
        uint256 spigotOperatorTokensBefore = spigot.getOperatorTokens(USDC);

        // If the contract code were correct, ie without the bug, the following commented-out assertion
        // would throw:
        // assertEq(balanceBefore, spigotOwnerTokensBefore + spigotOperatorTokensBefore); d

        uint256 newTokens = line.claimAndRepay(USDC,hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000149970000000000000000000000000000000000000000000000000128e269a9e9abf4100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd000000000000000000000000e9039a6968ed998139e023ed8d41c7fa77b7ff7a0000000000000000000000000000000000000000000000b9a844386663f6ab7a");
        emit log_named_uint("newTokens", newTokens);

        uint256 balanceAfter = IERC20(USDC).balanceOf(address(spigot));
        uint256 spigotOwnerTokensAfter = spigot.getOwnerTokens(USDC); 
        uint256 spigotOperatorTokensAfter = spigot.getOperatorTokens(USDC);

        assertEq(spigotOwnerTokensAfter, 0);

        // the owner tokens should all be used up and the spigot's balance should reduce accordingly
        assertEq(balanceAfter, balanceBefore - spigotOwnerTokensBefore);

        // revenue isn't being claimed, so operator tokens remain unchanged
        assertEq(spigotOperatorTokensBefore, spigotOperatorTokensAfter, "operator tokens dont match");
        vm.stopPrank();
    }

    // note:    This is an alternative version of the test above for block 16_187_712.  The spigot
    //          balance should be equal to the sum of the owner and operator tokens
    function testFail_mainnet_claimAndRepay_after_claiming_revenue() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_687_712-1);

        uint256 balanceBefore = IERC20(USDC).balanceOf(address(spigot));
        uint256 spigotOwnerTokensBefore = spigot.getOwnerTokens(USDC); 
        uint256 spigotOperatorTokensBefore = spigot.getOperatorTokens(USDC);

        assertEq(balanceBefore, spigotOwnerTokensBefore + spigotOperatorTokensBefore );
    }

    // note:    Revenue is claimed, and because it's the first claim after `claimAndRepay` has been
    //          been called, the accounting bug does not take effect yet.
    // 16_693_128: claimRevenue
    // https://etherscan.io/tx/0xc3e0aa99d9d1594d1f07e40281231b4f0173d5be8b900a2b133f899fea038f1e
    
    function test_mainnet_claimRevenue_after_transfer() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_693_128-1);

        // 15 USDC is transferred to the spigot as revenue in the following transaction:
        // https://etherscan.io/tx/0x612b73ae52df451869874341075e9a0d083b20827d140d1779268d28b0e34c49
        vm.startPrank(BORROWER);
        uint256 spigotBalanceBefore =IERC20(USDC).balanceOf(address(spigot));
        uint256 spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        uint256 spigotOperatorTokens = spigot.getOperatorTokens(USDC);

        uint256 previousSpigotOperatorTokens = spigot.getOperatorTokens(USDC);
        uint256 claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));
        emit log_named_uint("claimed", claimed);
        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        uint256 expectedOwnerTokens = (claimed * revenueSplit) / 100;

        assertEq(spigotOwnerTokens, expectedOwnerTokens);
        assertEq(spigotOperatorTokens, previousSpigotOperatorTokens + (claimed * (100-revenueSplit)) / 100);
        assertEq(spigotOperatorTokens, claimed - expectedOwnerTokens + previousSpigotOperatorTokens);
        vm.stopPrank();
    }


    // note:    This is an alternative version of the test above for block 16_693_128.  The spigot
    //          balance should be equal to the sum of the owner and operator tokens after claiming revenue.
    function testFail_mainnet_claimRevenue_after_transfer() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_693_128-1);

        // 15 USDC is transferred to the spigot as revenue in the following transaction:
        // https://etherscan.io/tx/0x612b73ae52df451869874341075e9a0d083b20827d140d1779268d28b0e34c49
        vm.startPrank(BORROWER);
        uint256 claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));
        uint256 spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        uint256 spigotOperatorTokens = spigot.getOperatorTokens(USDC);

        assertEq(IERC20(USDC).balanceOf(address(spigot)), spigotOwnerTokens+spigotOperatorTokens );
        vm.stopPrank();
    }

    // 16_694_077: claimRevenue
    // https://etherscan.io/tx/0xe390d3d2baf3b0701140b974aab9c4622ddc8bc43c019f15a5fb1ff3c6223a3c
    function test_mainnet_claimRevenue_again_after_transfer() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_694_077-1);

        vm.startPrank(BORROWER);

        uint256 spigotBalanceBefore = IERC20(USDC).balanceOf(address(spigot));
        emit log_named_uint("spigotBalanceBefore", spigotBalanceBefore);
        uint256 spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        emit log_named_uint("spigotOwnerTokens", spigotOwnerTokens);
        uint256 previousSpigotOperatorTokens = spigot.getOperatorTokens(USDC);
        emit log_named_uint("spigotOperatorTokens",spigotOperatorTokens );

        // without the bug in the contract, this TX would revert as their should be no revenue to claim
        uint256 claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));
        emit log_named_uint("claimed", claimed);

        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        uint256 spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        uint256 expectedOwnerTokens = (claimed * revenueSplit) / 100;

        // the following would revert if the spigotLib accounting was correct
        // assertEq(spigotOwnerTokens, expectedOwnerTokens, "owner token mismatch");
        // assertEq(spigotOperatorTokens, previousSpigotOperatorTokens + (claimed * (100-revenueSplit)) / 100, "operator token mismatch");

        vm.stopPrank();
    }

    // note:    This is an alternative version of the test above for block 16_694_077.  The expected amount
    //          of ownerTokens and operatorTokens should be proportional to the claim as dictated by the revenueSplit.
    function testFail_mainnet_claimRevenue_again_after_transfer() public {
        vm.createSelectFork(MAINNET_RPC_URL, 16_694_077-1);
        vm.startPrank(BORROWER);
        
        uint256 spigotBalanceBefore = IERC20(USDC).balanceOf(address(spigot));
        uint256 spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        uint256 previousSpigotOperatorTokens = spigot.getOperatorTokens(USDC);

        // without the bug in the contract, this TX would revert as their should be no revenue to claim
        uint256 claimed = spigot.claimRevenue(BORROWER_REVENUE_EOA, USDC, bytes(""));

        spigotOwnerTokens = spigot.getOwnerTokens(USDC);
        uint256 spigotOperatorTokens = spigot.getOperatorTokens(USDC);
        uint256 expectedOwnerTokens = (claimed * revenueSplit) / 100;

        assertEq(spigotOwnerTokens, expectedOwnerTokens);        
        assertEq(spigotOperatorTokens, previousSpigotOperatorTokens + (claimed * (100-revenueSplit)) / 100);

        vm.stopPrank();
    }

}
