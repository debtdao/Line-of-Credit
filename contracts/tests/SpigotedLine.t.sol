pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {ZeroEx} from "../mock/ZeroEx.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";
import {RevenueToken} from "../mock/RevenueToken.sol";

import {Spigot} from "../modules/spigot/Spigot.sol";
import {SpigotedLine} from "../modules/credit/SpigotedLine.sol";

import {LineLib} from "../utils/LineLib.sol";
import {SpigotedLineLib} from "../utils/SpigotedLineLib.sol";

import {ISpigot} from "../interfaces/ISpigot.sol";
import {ISpigotedLine} from "../interfaces/ISpigotedLine.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";

/**
 * @notice
 * @dev - does not test spigot integration e.g. claimEscrow() since that should already be covered in Spigot tests
 * - these tests would fail if that assumption was wrong anyway
 */
contract SpigotedLineTest is Test {
    ZeroEx dex;
    SpigotedLine line;
    Spigot spigot;

    RevenueToken creditToken;
    RevenueToken revenueToken;

    // Named vars for common inputs
    address constant revenueContract = address(0xdebf);
    uint256 lentAmount = 1 ether;

    uint128 constant drawnRate = 100;
    uint128 constant facilityRate = 1;
    uint256 constant ttl = 10 days; // allows us t
    uint8 constant ownerSplit = 10; // 10% of all borrower revenue goes to spigot

    uint256 constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 constant MAX_REVENUE = MAX_INT / 100;

    // Line access control vars
    address private arbiter = address(this);
    address private borrower = address(10);
    address private lender = address(20);

    address private testaddr = makeAddr("test");
    SimpleOracle private oracle;

    function setUp() public {
        console.log(testaddr);
        dex = new ZeroEx();
        creditToken = new RevenueToken();
        revenueToken = new RevenueToken();

        oracle = new SimpleOracle(address(revenueToken), address(creditToken));
        spigot = new Spigot(address(this), borrower, borrower);

        line = new SpigotedLine(
          address(oracle),
          arbiter,
          borrower,
          address(spigot),
          payable(address(dex)),
          ttl,
          ownerSplit
        );

        spigot.updateOwner(address(line));

        line.init();

        _mintAndApprove();

        _createCredit(address(revenueToken), address(creditToken), revenueContract);
        // revenue go brrrrrrr
        spigot.claimRevenue(address(revenueContract), "");
    }

    function _createCredit(address revenueT, address creditT, address revenueC) public returns (bytes32 id) {
        ISpigot.Setting memory setting = ISpigot.Setting({
            token: revenueT,
            ownerSplit: ownerSplit,
            claimFunction: bytes4(0),
            transferOwnerFunction: bytes4("1234")
        });

        oracle.changePrice(creditT, int256(1 ether)); // whitelist token

        startHoax(borrower);
        line.addCredit(drawnRate, facilityRate, lentAmount, creditT, lender);
        line.addSpigot(revenueC, setting);
        vm.stopPrank();

        startHoax(lender);
        if (creditT != Denominations.ETH) {
            deal(creditT, lender, MAX_REVENUE);
            RevenueToken(creditT).approve(address(line), MAX_INT);
            id = line.addCredit(drawnRate, facilityRate, lentAmount, creditT, lender);
        } else {
            id = line.addCredit{value: lentAmount}(drawnRate, facilityRate, lentAmount, creditT, lender);
        }
        vm.stopPrank();

        // as arbiter
        hoax(arbiter);
        line.addSpigot(revenueC, setting);
        vm.stopPrank();
    }

    function _borrow(bytes32 id, uint256 amount) public {
        vm.startPrank(borrower);
        line.borrow(id, amount);
        vm.stopPrank();
    }

    function _mintAndApprove() public {
        // ETH
        deal(address(dex), MAX_REVENUE);
        deal(address(borrower), MAX_REVENUE);
        deal(address(lender), MAX_REVENUE);

        // seed dex with tokens to buy
        creditToken.mint(address(dex), MAX_REVENUE);
        // allow line to use tokens for depositAndRepay()
        creditToken.mint(lender, MAX_REVENUE);
        creditToken.mint(address(this), MAX_REVENUE);
        creditToken.approve(address(line), MAX_INT);
        // allow trades
        creditToken.approve(address(dex), MAX_INT);

        // tokens to trade

        revenueToken.mint(borrower, MAX_REVENUE);
        revenueToken.mint(address(line), MAX_REVENUE);
        revenueToken.mint(address(dex), MAX_REVENUE);
        revenueToken.mint(address(this), MAX_REVENUE);
        revenueToken.approve(address(dex), MAX_INT);

        // revenue earned
        revenueToken.mint(address(spigot), MAX_REVENUE);
        // allow deposits
        revenueToken.approve(address(line), MAX_INT);
    }

    // claimAndTrade

    // TODO add raw ETH tests

    function test_can_use_claimed_revenue_to_trade() public {
        _borrow(line.ids(0), lentAmount);

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), address(creditToken), claimable, 1
        );

        hoax(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);

        // dex balances
        assertEq(creditToken.balanceOf((address(dex))), MAX_REVENUE - 1);
        assertEq(revenueToken.balanceOf((address(dex))), MAX_REVENUE + claimable);
        // line balances
        assertEq(creditToken.balanceOf((address(line))), 1);
        assertEq(revenueToken.balanceOf((address(line))), MAX_REVENUE);
    }

    function test_no_unused_revenue_tokens_to_trade() public {
        _borrow(line.ids(0), lentAmount);

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        // no extra tokens besides claimable
        assertEq(line.unused(address(revenueToken)), 0);
        // Line already has tokens minted to it that we can try and steal as borrower
        assertEq(revenueToken.balanceOf(address(line)), MAX_REVENUE);

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimable + 1, // try spendnig more tokens than claimed
            1
        );

        hoax(borrower);
        // No unused tokens so can't get approved
        vm.expectRevert(SpigotedLineLib.TradeFailed.selector);
        line.claimAndTrade(address(revenueToken), tradeData);
    }

    // need to emit event to test if is emitted in function call
    event TradeSpigotRevenue(
        address indexed revenueToken,
        uint256 revenueTokenAmount,
        address indexed debtToken,
        uint256 indexed debtTokensBought
    );

    function test_does_not_trade_if_rev_credit_same_token() public {
        address revenueC = address(0xbeef);
        // reverse rev/credit so we can test each way
        address creditT = address(creditToken);
        _borrow(line.ids(0), lentAmount);

        // attach spigot for creditT and claim
        bytes32 id = _createCredit(creditT, address(revenueToken), revenueC);
        // generate revenue in credit token
        deal(creditT, address(spigot), 100 ether);
        spigot.claimRevenue(revenueC, "");
        uint256 claimable = spigot.getEscrowed(address(creditT));

        // no extra tokens besides claimable
        assertEq(line.unused(creditT), 0);

        // test claimAndTrade + claimAndRepay
        bytes memory tradeData =
            abi.encodeWithSignature("trade(address,address,uint256,uint256)", creditT, creditT, claimable, 15 ether);

        hoax(borrower);

        // wierd setup bc  only way to tell if we didnt trade from outside is events/calls
        // but claimEscrow is called in both branches so can only test for DEX interacvtions

        // we say we expect a trade event (A)
        // then say we expect our expectation to fail (B)
        // when tokens aren't traded (C)
        vm.expectRevert("Log != expected log"); // (B)
        try line.claimAndTrade(creditT, tradeData) /* (C) */ returns (uint256) {
            // say that we expect the tokens to be traded
            vm.expectEmit(true, true, true, true); // (A)
            emit TradeSpigotRevenue(creditT, claimable, creditT, 15 ether);
        } catch {}
    }

    function test_no_unused_credit_tokens_to_trade() public {
        _borrow(line.ids(0), lentAmount);

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        // if(claimable == 0) { // ensure claimAndRepay doesnt fail from claimEscrow()
        deal(address(revenueToken), address(spigot), MAX_REVENUE);
        spigot.claimRevenue(revenueContract, "");
        claimable = spigot.getEscrowed(address(revenueToken));
        // }

        // no extra tokens
        assertEq(line.unused(address(creditToken)), 0);
        // Line already has tokens minted to it that we can try and steal as borrower
        assertEq(creditToken.balanceOf(address(line)), 0);

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimable,
            0 // no credit tokens bought at all
        );

        // No unused tokens so can't get approved
        vm.startPrank(borrower);
        vm.expectRevert(SpigotedLineLib.TradeFailed.selector);
        line.claimAndTrade(address(revenueToken), tradeData);
        (, uint256 p,,,,,) = line.credits(line.ids(0));

        assertEq(p, lentAmount); // nothing repaid

        vm.expectRevert();
        line.useAndRepay(1);
        vm.stopPrank();
    }

    function test_increase_unused_revenue(uint256 buyAmount, uint256 sellAmount) public {
        if (buyAmount == 0 || sellAmount == 0) {
            return;
        }
        if (buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) {
            return;
        }

        // need to have active position so we can buy asset
        _borrow(line.ids(0), lentAmount);

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimable - 1,
            lentAmount / 2
        );

        // make unused tokens available
        hoax(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);

        assertEq(line.unused(address(revenueToken)), 1);
        assertEq(revenueToken.balanceOf(address(line)), MAX_REVENUE + 1);
        assertEq(revenueToken.balanceOf(address(dex)), MAX_REVENUE + claimable - 1);
    }

    function test_decrease_unused_revenue(uint256 buyAmount, uint256 sellAmount) public {
        if (buyAmount == 0 || sellAmount == 0) {
            return;
        }
        if (buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) {
            return;
        }

        // need to have active position so we can buy asset
        _borrow(line.ids(0), lentAmount);

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimable - 1,
            lentAmount / 2
        );

        // make unused tokens available
        vm.startPrank(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);

        assertEq(line.unused(address(revenueToken)), 1);

        revenueToken.mint(address(spigot), MAX_REVENUE);
        spigot.claimRevenue(address(revenueContract), "");

        bytes memory tradeData2 = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), address(creditToken), claimable + 1, 1
        );

        line.claimAndTrade(address(revenueToken), tradeData2);
        assertEq(line.unused(address(revenueToken)), 0);
        vm.stopPrank();
    }

    function test_increase_unused_debt(uint256 buyAmount, uint256 sellAmount) public {
        if (buyAmount == 0 || sellAmount == 0) {
            return;
        }
        if (buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) {
            return;
        }

        // need to have active position so we can buy asset
        _borrow(line.ids(0), lentAmount);

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimable,
            lentAmount / 2
        );

        // make unused tokens available
        hoax(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);

        assertEq(line.unused(address(creditToken)), lentAmount / 2);
    }

    function test_decrease_unused_debt(uint256 buyAmount, uint256 sellAmount) public {
        // effectively the same but want to denot that they can be two separate tests
        return test_can_repay_with_unused_tokens(buyAmount, sellAmount);
    }

    function test_can_repay_with_unused_tokens(uint256 buyAmount, uint256 sellAmount) public {
        // oracle prices not relevant to test
        if (buyAmount == 0 || sellAmount == 0) {
            return;
        }
        if (buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) {
            return;
        }

        // need to have active position so we can buy asset
        _borrow(line.ids(0), lentAmount);

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimable,
            lentAmount / 2
        );

        // make unused tokens available
        vm.startPrank(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);

        assertEq(line.unused(address(creditToken)), lentAmount / 2);

        revenueToken.mint(address(spigot), MAX_REVENUE);
        spigot.claimRevenue(address(revenueContract), "");

        bytes memory repayData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimable,
            lentAmount / 2
        );

        line.claimAndRepay(address(revenueToken), repayData);
        (, uint256 p,,,,,) = line.credits(line.ids(0));
        vm.stopPrank();

        assertEq(p, 0);
        assertEq(line.unused(address(creditToken)), 0); // used first half to make up for second half missing
    }

    // trades work

    function test_can_trade(uint256 buyAmount, uint256 sellAmount) public {
        // oracle prices not relevant to test
        if (buyAmount == 0 || sellAmount == 0) {
            return;
        }
        if (buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) {
            return;
        }

        // need to have active position so we can buy asset
        _borrow(line.ids(0), lentAmount);

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), address(creditToken), sellAmount, buyAmount
        );

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        vm.prank(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);

        // TODO this got merged in, maybe removable
        if (claimable > sellAmount) {
            // we properly test unused token logic elsewhere but still checking here
            assertEq(claimable - sellAmount, line.unused(address(revenueToken)));
        }

        // dex balances
        assertEq(creditToken.balanceOf((address(dex))), MAX_REVENUE - buyAmount);
        assertEq(revenueToken.balanceOf((address(dex))), MAX_REVENUE + sellAmount);

        // also check credit balances;
        assertEq(creditToken.balanceOf((address(line))), buyAmount);
        assertEq(revenueToken.balanceOf((address(line))), MAX_REVENUE + claimable - sellAmount);
    }

    function test_cant_claim_and_trade_not_borrowing() public {
        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), address(creditToken), lentAmount, lentAmount
        );

        vm.expectRevert(ILineOfCredit.NotBorrowing.selector);
        hoax(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);
    }

    function test_cant_claim_and_repay_not_borrowing() public {
        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), address(creditToken), lentAmount, lentAmount
        );

        vm.expectRevert(ILineOfCredit.NotBorrowing.selector);
        line.claimAndRepay(address(revenueToken), tradeData);
    }

    function test_can_trade_and_repay_ETH_revenue(uint256 ethRevenue) public {
        if (ethRevenue <= 100 || ethRevenue > MAX_REVENUE) {
            return;
        } // min/max amount of revenue spigot accepts
        _mintAndApprove(); // create more tokens since we are adding another position
        address revenueC = address(0xbeef);
        address creditT = address(new RevenueToken());
        bytes32 id = _createCredit(Denominations.ETH, creditT, revenueC);
        deal(address(spigot), ethRevenue);
        deal(creditT, address(dex), MAX_REVENUE);

        spigot.claimRevenue(revenueC, "");

        _borrow(id, lentAmount);

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            Denominations.ETH,
            creditT,
            (ethRevenue * ownerSplit) / 100,
            lentAmount
        );

        uint256 claimable = spigot.getEscrowed(Denominations.ETH);

        hoax(borrower);
        line.claimAndTrade(Denominations.ETH, tradeData);

        assertEq(line.unused(creditT), lentAmount);
    }

    function test_can_trade_for_ETH_debt() public {
        deal(address(lender), lentAmount + 1 ether);
        deal(address(revenueToken), MAX_REVENUE);
        address revenueC = address(0xbeef); // need new spigot for testing
        bytes32 id = _createCredit(address(revenueToken), Denominations.ETH, revenueC);
        _borrow(id, lentAmount);

        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), Denominations.ETH, 1 gwei, lentAmount
        );

        uint256 claimable = spigot.getEscrowed(address(revenueToken));
        hoax(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);
        assertEq(line.unused(Denominations.ETH), lentAmount);
    }

    function test_can_trade_and_repay(uint256 buyAmount, uint256 sellAmount, uint256 timespan) public {
        if (timespan > ttl) {
            return;
        }
        if (buyAmount == 0 || sellAmount == 0) {
            return;
        }
        if (buyAmount >= MAX_REVENUE || sellAmount >= MAX_REVENUE) {
            return;
        }

        _borrow(line.ids(0), lentAmount);

        // no interest charged because no blocks processed
        uint256 interest = 0;

        // vm.warp(timespan);
        // line.accrueInterest();
        // (,,uint interest,,,,) = line.credits(line.ids(0)) ;

        // oracle prices not relevant to trading test
        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), address(creditToken), sellAmount, buyAmount
        );

        uint256 claimable = spigot.getEscrowed(address(revenueToken));

        vm.prank(borrower);
        console.log(buyAmount);
        console.log(sellAmount);
        line.claimAndRepay(address(revenueToken), tradeData);

        // principal, interest, repaid
        (, uint256 p, uint256 i, uint256 r,,,) = line.credits(line.ids(0));

        // outstanding debt = initial principal + accrued interest - tokens repaid
        uint256 _buyAmount = buyAmount > lentAmount + interest ? lentAmount + interest : buyAmount;
        console.log(p + i);
        console.log(lentAmount + interest);
        assertEq(p + i, lentAmount + interest - _buyAmount, "first assert");

        if (interest > buyAmount) {
            // only interest paid
            assertEq(r, buyAmount); // paid what interest we could
            assertEq(i, interest - buyAmount); // interest owed should be reduced by repay amount
            assertEq(p, lentAmount); // no change in principal
        } else {
            assertEq(p, buyAmount > lentAmount + interest ? 0 : lentAmount - (buyAmount - interest));
            assertEq(i, 0); // all interest repaid
            assertEq(r, interest); // all interest repaid
        }
        emit log_named_uint("----  BUY AMOUNT ----", buyAmount);
        emit log_named_uint("----  SELL AMOUNT ----", sellAmount);

        uint256 unusedCreditToken = buyAmount < lentAmount ? 0 : buyAmount - lentAmount;
        uint256 unusedRevenueToken = sellAmount > claimable ? 0 : claimable - sellAmount;
        assertEq(line.unused(address(creditToken)), unusedCreditToken, "2nd to last assert");

        assertEq(line.unused(address(revenueToken)), unusedRevenueToken, "last assert");
    }

    // write tests for unused tokens

    // check unsused balances. Do so by changing minAmountOut in trade 0
    function test_anyone_can_deposit_and_repay() public {
        _borrow(line.ids(0), lentAmount);

        creditToken.mint(address(0xdebf), lentAmount);
        hoax(address(0xdebf));
        creditToken.approve(address(line), lentAmount);
        line.depositAndRepay(lentAmount);
    }

    // Spigot integration tests
    // results change based on line status (ACTIVE vs LIQUIDATABLE vs INSOLVENT)
    // Only checking that Line functions dont fail. Check `Spigot.t.sol` for expected functionality

    // releaseSpigot()

    function test_release_spigot_while_active() public {
        assertFalse(line.releaseSpigot());
    }

    function test_release_spigot_to_borrower_when_repaid() public {
        vm.startPrank(borrower);
        line.close(line.ids(0));
        vm.stopPrank();

        hoax(borrower);
        assertTrue(line.releaseSpigot());

        assertEq(spigot.owner(), borrower);
    }

    function test_only_borrower_release_spigot_when_repaid() public {
        vm.startPrank(borrower);
        line.close(line.ids(0));
        vm.stopPrank();

        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        line.releaseSpigot();
    }

    function test_release_spigot_to_arbiter_when_liquidated() public {
        vm.warp(ttl + 1);

        assertTrue(line.releaseSpigot());

        assertEq(spigot.owner(), arbiter);
    }

    function test_only_arbiter_release_spigot_when_liquidated() public {
        vm.warp(ttl + 1);

        hoax(lender);
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        line.releaseSpigot();
    }
    // sweep()

    function test_cant_sweep_tokens_while_active() public {
        _borrow(line.ids(0), lentAmount);
        uint256 claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amountd tokens for test
        // create unused tokens
        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), address(creditToken), claimed - 1, lentAmount
        );
        hoax(borrower);
        line.claimAndTrade(address(revenueToken), tradeData);
        vm.stopPrank();

        assertEq(0, line.sweep(address(this), address(creditToken))); // no tokens transfered
    }

    function test_cant_sweep_empty_tokens() public {
        vm.expectRevert(abi.encodeWithSelector(SpigotedLineLib.UsedExcessTokens.selector, address(creditToken), 0));
        line.sweep(address(this), address(creditToken));
    }

    function test_cant_sweep_tokens_when_repaid_as_anon() public {
        _borrow(line.ids(0), lentAmount);
        uint256 claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amountd tokens for test
        // create unused tokens
        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimed - 1,
            lentAmount + 1 ether // give excess tokens so we can sweep with out UsedExcess error
        );

        hoax(borrower);
        line.claimAndRepay(address(revenueToken), tradeData);
        bytes32 id = line.ids(0);
        hoax(borrower);
        line.close(id);
        assertEq(uint256(line.status()), uint256(LineLib.STATUS.REPAID));

        hoax(address(0xdebf));
        vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
        assertEq(0, line.sweep(address(this), address(creditToken))); // no tokens transfered
    }

    function test_sweep_to_borrower_when_repaid() public {
        _borrow(line.ids(0), lentAmount);

        uint256 claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amount
        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            claimed - 10,
            lentAmount + 1 ether // give excess tokens so we can sweep with out UsedExcess error
        );

        line.claimAndRepay(address(revenueToken), tradeData);

        bytes32 id = line.ids(0);
        hoax(borrower);
        line.close(id);

        // initial mint + spigot revenue to borrower (- unused?)
        uint256 balance = revenueToken.balanceOf(address(borrower));
        assertEq(balance, MAX_REVENUE + ((MAX_REVENUE * 9) / 10) + 1); // tbh idk y its +1 here

        uint256 unused = line.unused(address(revenueToken));
        hoax(borrower);
        uint256 swept = line.sweep(address(borrower), address(revenueToken));

        assertEq(unused, 10); // all unused sent to arbi
        assertEq(swept, unused); // all unused sent to arbi
        assertEq(swept, 10); // untraded revenue
        assertEq(swept, revenueToken.balanceOf(address(borrower)) - balance); // arbi balance updates properly
    }

    function test_cant_sweep_tokens_when_liquidate_as_anon() public {
        _borrow(line.ids(0), lentAmount);
        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)",
            address(revenueToken),
            address(creditToken),
            MAX_REVENUE / 100,
            lentAmount // give excess tokens so we can sweep with out UsedExcess error
        );
        hoax(borrower);

        line.claimAndTrade(address(revenueToken), tradeData);

        vm.warp(ttl + 1);

        hoax(address(0xdebf));
        vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
        assertEq(0, line.sweep(address(this), address(creditToken))); // no tokens transfered
    }

    function test_sweep_to_arbiter_when_liquidated() public {
        _borrow(line.ids(0), lentAmount);

        uint256 claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amount

        hoax(borrower);
        bytes memory tradeData = abi.encodeWithSignature(
            "trade(address,address,uint256,uint256)", address(revenueToken), address(creditToken), claimed - 1, lentAmount
        );
        line.claimAndRepay(address(revenueToken), tradeData);
        vm.stopPrank();

        assertEq(uint256(line.status()), uint256(LineLib.STATUS.ACTIVE));

        uint256 balance = revenueToken.balanceOf(address(arbiter));
        uint256 unused = line.unused(address(revenueToken));

        vm.warp(ttl + 1); // set to liquidatable

        uint256 swept = line.sweep(address(this), address(revenueToken));
        assertEq(swept, unused); // all unused sent to arbiter
        assertEq(swept, 1); // untraded revenue
        assertEq(swept, revenueToken.balanceOf(address(arbiter)) - balance); // arbiter balance updates properly
    }

    // updateOwnerSplit()

    function test_split_must_be_lte_100(uint8 proposedSplit) public {
        if (proposedSplit > 100) {
            vm.expectRevert();
        }

        new SpigotedLine(
          address(oracle),
          arbiter,
          borrower,
          address(spigot),
          payable(address(dex)),
          ttl,
          proposedSplit
        );
    }

    function test_update_split_no_action_on_active() public {
        // already at default so doesnt change
        assertFalse(line.updateOwnerSplit(revenueContract));
    }

    function test_update_split_no_action_on_already_liquidated() public {
        // validate original settings
        (, uint8 split,,) = spigot.getSetting(revenueContract);
        assertEq(split, ownerSplit);

        // fast forward to past deadline
        vm.warp(ttl + 1);

        assertTrue(line.updateOwnerSplit(revenueContract));
        (, uint8 split2,,) = spigot.getSetting(revenueContract);
        assertEq(split2, 100); // to 100 since LIQUIDATABLE

        // second run shouldnt updte
        assertFalse(line.updateOwnerSplit(revenueContract));
        // split should still be 100%
        (, uint8 split3,,) = spigot.getSetting(revenueContract);
        assertEq(split3, 100);
    }

    function test_update_split_bad_contract() public {
        vm.expectRevert(SpigotedLineLib.NoSpigot.selector);
        line.updateOwnerSplit(address(0xdead));
    }

    function test_update_split_to_100_on_liquidate() public {
        // fast forward to past deadline
        vm.warp(ttl + 1);

        assertTrue(line.updateOwnerSplit(revenueContract));
        assertEq(uint256(line.status()), uint256(LineLib.STATUS.LIQUIDATABLE));
        (, uint8 split,,) = spigot.getSetting(revenueContract);
        assertEq(split, 100);
    }

    function test_update_split_to_default_on_active_from_liquidate() public {
        // validate original settings
        (, uint8 split,,) = spigot.getSetting(revenueContract);
        assertEq(split, ownerSplit);

        // fast forward to past deadline
        vm.warp(ttl + 1);

        assertTrue(line.updateOwnerSplit(revenueContract));
        assertEq(uint256(line.status()), uint256(LineLib.STATUS.LIQUIDATABLE));
        (, uint8 split2,,) = spigot.getSetting(revenueContract);
        assertEq(split2, 100); // to 100 since LIQUIDATABLE

        vm.warp(1); // sstatus = LIQUIDTABLE but healthcheck == ACTIVE
        assertTrue(line.updateOwnerSplit(revenueContract));
        (, uint8 split3,,) = spigot.getSetting(revenueContract);
        assertEq(split3, ownerSplit); // to default since ACTIVE
    }

    // addSpigot()

    function test_cant_add_spigot_without_consent() public {
        address rev = address(0xf1c0);
        ISpigot.Setting memory setting = ISpigot.Setting({
            token: address(revenueToken),
            ownerSplit: ownerSplit,
            claimFunction: bytes4(0),
            transferOwnerFunction: bytes4("1234")
        });

        line.addSpigot(rev, setting);
        (address token,,, bytes4 transferFunc) = spigot.getSetting(rev);
        // settings not saved on spigot contract
        assertEq(transferFunc, bytes4(0));
        assertEq(token, address(0));
    }

    function test_can_add_spigot_with_consent() public {
        address rev = address(0xf1c0);
        ISpigot.Setting memory setting = ISpigot.Setting({
            token: address(revenueToken),
            ownerSplit: ownerSplit,
            claimFunction: bytes4(0),
            transferOwnerFunction: bytes4("1234")
        });

        line.addSpigot(rev, setting);
        hoax(borrower);
        line.addSpigot(rev, setting);

        (address token, uint8 split, bytes4 claim, bytes4 transfer) = spigot.getSetting(rev);
        // settings not saved on spigot contract
        assertEq(transfer, setting.transferOwnerFunction);
        assertEq(claim, setting.claimFunction);
        assertEq(token, setting.token);
        assertEq(split, setting.ownerSplit);
    }

    // updateWhitelist
    function test_cant_whitelist_as_anon() public {
        hoax(address(0xdebf));
        vm.expectRevert();
        line.updateWhitelist(bytes4("0000"), true);
    }

    function test_cant_whitelist_as_borrower() public {
        hoax(borrower);
        vm.expectRevert();
        line.updateWhitelist(bytes4("0000"), true);
    }

    function test_can_whitelist_as_arbiter() public {
        assertTrue(line.updateWhitelist(bytes4("0000"), true));
    }
}
