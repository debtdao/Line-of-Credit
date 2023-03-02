
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import { Denominations } from "chainlink/Denominations.sol";

import { ZeroEx } from "../mock/ZeroEx.sol";
import { SimpleOracle } from "../mock/SimpleOracle.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";

import {MutualConsent} from "../utils/MutualConsent.sol";

import { Spigot } from "../modules/spigot/Spigot.sol";
import { SpigotedLine } from '../modules/credit/SpigotedLine.sol';

import { LineLib } from '../utils/LineLib.sol';
import { SpigotedLineLib } from '../utils/SpigotedLineLib.sol';

import { ISpigot } from '../interfaces/ISpigot.sol';
import { ISpigotedLine } from '../interfaces/ISpigotedLine.sol';
import { ILineOfCredit } from '../interfaces/ILineOfCredit.sol';

interface Events {
      event ReservesChanged (
        address indexed token,
        int256 indexed diff,
        uint256 tokenType       // 0 for revenue token, 1 for credit token
    ); 
}
/**
 * @notice
 * @dev - does not test spigot integration e.g. claimEscrow() since that should already be covered in Spigot tests
 *      - these tests would fail if that assumption was wrong anyway
 */
contract SpigotedLineTest is Test, Events {
    ZeroEx dex;
    SpigotedLine line;
    Spigot spigot;

    RevenueToken creditToken;
    RevenueToken revenueToken;

    // Named vars for common inputs
    address constant revenueContract = address(0xdebf);
    uint lentAmount = 1 ether;
    
    uint128 constant dRate = 100;
    uint128 constant fRate = 1;
    uint constant ttl = 10 days; // allows us t
    uint8 constant ownerSplit = 10; // 10% of all borrower revenue goes to spigot

    uint MAX_INT = type(uint256).max;
    uint MAX_REVENUE = MAX_INT / 10**18;

    // Line access control vars
    address private arbiter = address(this);
    address private borrower = address(10);
    address private lender = address(20);

    address private testaddr = makeAddr("test");
    SimpleOracle private oracle;

    function setUp() public {
        dex = new ZeroEx();
        creditToken = new RevenueToken();
        revenueToken = new RevenueToken();

        oracle = new SimpleOracle(address(revenueToken), address(creditToken));
        spigot = new Spigot(address(this), borrower);
        
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
        spigot.claimRevenue(address(revenueContract), address(revenueToken), "");
    }

    function _generateRevenueAndClaim(uint256 revenue) internal {
      revenueToken.mint(address(spigot), revenue);
      spigot.claimRevenue(address(revenueContract), address(revenueToken), "");
    }

    function _createCredit(address revenueT, address creditT, address revenueC) public returns(bytes32 id) {

      if (creditT == Denominations.ETH) revert("Eth not supported");

      ISpigot.Setting memory setting = ISpigot.Setting({
        // token: revenueT,
        ownerSplit: ownerSplit,
        claimFunction: bytes4(0),
        transferOwnerFunction: bytes4("1234")
      });

      oracle.changePrice(creditT, int(1 ether)); // whitelist token

      startHoax(borrower);
      line.addCredit(dRate, fRate, lentAmount, creditT, lender);
      vm.stopPrank();
      
      startHoax(lender);
      deal(creditT, lender, MAX_REVENUE);
      RevenueToken(creditT).approve(address(line), MAX_INT);
      id = line.addCredit(dRate, fRate, lentAmount, creditT, lender);
      vm.stopPrank();

      // as arbiter
      hoax(arbiter);
      line.addSpigot(revenueC, setting);
      vm.stopPrank();
    }

    function _createEthRevenue(address revenueC, uint256 revenue) internal {
      deal(revenueC, revenue);
    }

    function _borrow(bytes32 id, uint amount) public {
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
      revenueToken.mint(address(spigot), MAX_REVENUE / 2);
      // allow deposits
      revenueToken.approve(address(line), MAX_INT);
    }


    // claimAndTrade 
    
    // TODO add raw ETH tests

    function test_can_use_claimed_revenue_to_trade() public {
      _borrow(line.ids(0), lentAmount);

      uint claimable = spigot.getOwnerTokens(address(revenueToken));

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable,
        1
      );

      hoax(arbiter);
      vm.expectEmit(true, true, true, true);
      emit ReservesChanged(address(revenueToken), 0, 0);
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

      uint claimable = spigot.getOwnerTokens(address(revenueToken));
      
      // no extra tokens besides claimable
      assertEq(line.unused(address(revenueToken)), 0);
      // Line already has tokens minted to it that we can try and steal as borrower
      assertEq(revenueToken.balanceOf(address(line)), MAX_REVENUE);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable + 1, // try spendnig more tokens than claimed
        1
      );

      hoax(arbiter);
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
      spigot.claimRevenue(revenueC, address(creditT),  "");

      uint claimable = spigot.getOwnerTokens(address(revenueToken));
      
      // no extra tokens besides claimable
      assertEq(line.unused(creditT), 0);

      // test claimAndTrade + claimAndRepay
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        creditT,
        creditT,
        claimable,
        15 ether
      );


      // wierd setup bc  only way to tell if we didnt trade from outside is events/calls
      // but claimEscrow is called in both branches so can only test for DEX interacvtions
      
      // we say we expect a trade event (A)
      // then say we expect our expectation to fail (B) 
      // when tokens aren't traded (C)
      hoax(arbiter);
      vm.expectRevert("Log != expected log");  // (B)
      try line.claimAndTrade(creditT, tradeData) /* (C) */returns(uint256) {
        // say that we expect the tokens to be traded
        vm.expectEmit(true, true, true, true); // (A)
        emit TradeSpigotRevenue(creditT, claimable, creditT, 15 ether);
      } catch { }
    }

    function test_no_unused_credit_tokens_to_trade() public {
      _borrow(line.ids(0), lentAmount);

      uint256 spigotBalance = revenueToken.balanceOf(address(spigot));

      uint256 claimable = spigot.getOwnerTokens(address(revenueToken));
      uint256 operatorTokens = spigot.getOperatorTokens(address(revenueToken));

      assertGt(claimable, 0, "claimable amount is zero");
      // if(claimable == 0) { // ensure claimAndRepay doesnt fail from claimEscrow()
      revenueToken.mint(address(spigot), 1000 ether);
      spigotBalance = revenueToken.balanceOf(address(spigot));
      spigot.claimRevenue(revenueContract, address(revenueToken),  "");
      claimable = spigot.getOwnerTokens(address(revenueToken));
      // }
      
      // no extra tokens
      assertEq(line.unused(address(creditToken)), 0);
      // Line already has tokens minted to it that we can try and steal as borrower
      assertEq(creditToken.balanceOf(address(line)), 0);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable,
        0 // no credit tokens bought at all
      );

      // No unused tokens so can't get approved
      hoax(arbiter);
      vm.expectRevert(SpigotedLineLib.TradeFailed.selector);
      line.claimAndTrade(address(revenueToken), tradeData);
      (,uint p,,,,,,) = line.credits(line.ids(0));
      
      assertEq(p, lentAmount); // nothing repaid

      hoax(borrower);
      vm.expectRevert(
        abi.encodeWithSelector(
         ISpigotedLine.ReservesOverdrawn.selector,
         address(creditToken),
         0
        )
      );
      line.useAndRepay(1);
      vm.stopPrank();
    }

    function test_increase_unused_revenue(uint buyAmount, uint sellAmount) public {
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      
      // need to have active position so we can buy asset
      _borrow(line.ids(0), lentAmount);

      uint claimable = spigot.getOwnerTokens(address(revenueToken));

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable - 1,
        lentAmount / 2
      );

    // make unused tokens available
      hoax(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);

      assertEq(line.unused(address(revenueToken)), 1);
      assertEq(revenueToken.balanceOf(address(line)), MAX_REVENUE + 1);
      assertEq(revenueToken.balanceOf(address(dex)), MAX_REVENUE + claimable - 1);
    }

    function test_decrease_unused_revenue(uint buyAmount, uint sellAmount) public {

      buyAmount = bound(buyAmount, 1, MAX_REVENUE);
      sellAmount = bound(sellAmount, 1, MAX_REVENUE);
      
      // need to have active position so we can buy asset
      _borrow(line.ids(0), lentAmount);

      uint claimable = spigot.getOwnerTokens(address(revenueToken));

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable - 1,
        lentAmount / 2
      );

      // make unused tokens available
      vm.startPrank(arbiter);
      vm.expectEmit(true, true, true, true);
      emit ReservesChanged(address(revenueToken), 1, 0);
      line.claimAndTrade(address(revenueToken), tradeData);

      assertEq(line.unused(address(revenueToken)), 1);

      console.log("unused before", line.unused(address(revenueToken)));
      revenueToken.mint(address(spigot), MAX_REVENUE);
      spigot.claimRevenue(address(revenueContract), address(revenueToken), "");

      console.log("unused after", line.unused(address(revenueToken)));

      claimable = spigot.getOwnerTokens(address(revenueToken));

      bytes memory tradeData2 = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable + 1,
        1
      );

      vm.expectEmit(true, true, true, true);
      emit ReservesChanged(address(revenueToken), -1, 0);
      line.claimAndTrade(address(revenueToken), tradeData2);
      assertEq(line.unused(address(revenueToken)), 0, "unused revenue is not zero");
      vm.stopPrank();
    }

    function test_increase_unused_debt(uint buyAmount, uint sellAmount) public {
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      
      // need to have active position so we can buy asset
      _borrow(line.ids(0), lentAmount);

      uint claimable = spigot.getOwnerTokens(address(revenueToken));

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable,
        lentAmount / 2
      );

      // make unused tokens available
      hoax(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);

      assertEq(line.unused(address(creditToken)), lentAmount / 2);
    }

    function test_decrease_unused_debt(uint buyAmount, uint sellAmount) public {
      // effectively the same but want to denot that they can be two separate tests
      return test_can_repay_with_unused_tokens(buyAmount, sellAmount);
    }



    function test_can_repay_with_unused_tokens(uint buyAmount, uint sellAmount) public {
      // oracle prices not relevant to test
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      
      // need to have active position so we can buy asset
      _borrow(line.ids(0), lentAmount);

      uint claimable = spigot.getOwnerTokens(address(revenueToken));

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable,
        lentAmount / 2
      );

      // make unused tokens available
      vm.startPrank(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);

      assertEq(line.unused(address(creditToken)), lentAmount / 2);

      revenueToken.mint(address(spigot), MAX_REVENUE);
      spigot.claimRevenue(address(revenueContract), address(revenueToken), "");

      bytes memory repayData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable,
        lentAmount / 2
      );

      line.claimAndRepay(address(revenueToken), repayData);
      (,uint p,,,,,,) = line.credits(line.ids(0));
      vm.stopPrank();

      assertEq(p, 0);
      assertEq(line.unused(address(creditToken)), 0); // used first half to make up for second half missing
    }

    // trades work
  
    function test_can_trade(uint buyAmount, uint sellAmount) public {
      // oracle prices not relevant to test
      // if(buyAmount == 0 || sellAmount == 0) return;
      // if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      buyAmount = bound(buyAmount, 1, MAX_REVENUE - 1);
      sellAmount = bound(sellAmount, 1, MAX_REVENUE - 1);
      vm.assume(buyAmount < MAX_REVENUE);
      vm.assume(sellAmount < MAX_REVENUE);
      
      // need to have active position so we can buy asset
      _borrow(line.ids(0), lentAmount);


      uint claimable = spigot.getOwnerTokens(address(revenueToken));

      uint256 tradable;
      tradable = sellAmount > claimable ? claimable : sellAmount;

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        tradable,
        buyAmount
      );


      vm.prank(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);

      // TODO this got merged in, maybe removable
      if(claimable > sellAmount) {
        // we properly test unused token logic elsewhere but still checking here
        assertEq(claimable - sellAmount, line.unused(address(revenueToken)), "claimable - sellAmount != unused revenue");
      }
      
      // dex balances
      assertEq(creditToken.balanceOf((address(dex))), MAX_REVENUE - buyAmount);
      assertEq(revenueToken.balanceOf((address(dex))), MAX_REVENUE + tradable);
      
      // also check credit balances;
      assertEq(creditToken.balanceOf((address(line))), buyAmount);
      assertEq(revenueToken.balanceOf((address(line))), MAX_REVENUE + claimable - tradable);
    } 

    function test_cant_claim_and_trade_not_borrowing() public {
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        lentAmount,
        lentAmount
      );

      vm.expectRevert(ILineOfCredit.NotBorrowing.selector);
      hoax(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);
    }

    function test_cannot_claim_and_trade_if_borrower(uint buyAmount, uint sellAmount) public {
      // oracle prices not relevant to test
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      
      // need to have active position so we can buy asset
      _borrow(line.ids(0), lentAmount);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        sellAmount,
        buyAmount
      );

      uint claimable = spigot.getOwnerTokens(address(revenueToken));
      vm.expectRevert(ISpigot.CallerAccessDenied.selector);
      vm.prank(borrower);
      line.claimAndTrade(address(revenueToken), tradeData);
    }

    function test_cannot_claim_and_trade_if_lender(uint buyAmount, uint sellAmount) public {
      // oracle prices not relevant to test
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      
      // need to have active position so we can buy asset
      _borrow(line.ids(0), lentAmount);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        sellAmount,
        buyAmount
      );

      uint claimable = spigot.getOwnerTokens(address(revenueToken));
      vm.expectRevert(ISpigot.CallerAccessDenied.selector);
      vm.prank(lender);
      line.claimAndTrade(address(revenueToken), tradeData);
    }

    function test_cant_claim_and_repay_not_borrowing() public {
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        lentAmount,
        lentAmount
      );

      vm.expectRevert(ILineOfCredit.NotBorrowing.selector);
      line.claimAndRepay(address(revenueToken), tradeData);
    }

    function test_can_trade_and_repay_ETH_revenue(uint ethRevenue) public {
      if(ethRevenue <= 100 || ethRevenue > MAX_REVENUE) return; // min/max amount of revenue spigot accepts
      _mintAndApprove(); // create more tokens since we are adding another position
      address revenueC = address(0xbeef);
      address creditT = address(new RevenueToken());
      bytes32 id = _createCredit(Denominations.ETH, creditT, revenueC);
      deal(address(spigot), ethRevenue);
      deal(creditT, address(dex), MAX_REVENUE);

      spigot.claimRevenue(revenueC, address(Denominations.ETH), "");

      _borrow(id, lentAmount);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        Denominations.ETH,
        creditT,
        (ethRevenue * ownerSplit) / 100,
        lentAmount
      );

      uint claimable = spigot.getOwnerTokens(Denominations.ETH);

      hoax(arbiter);
      line.claimAndTrade(Denominations.ETH, tradeData);

      assertEq(line.unused(creditT), lentAmount);
    }

    function test_can_trade_ETH_revenue_for_debt()  public {
      deal(address(revenueToken), MAX_REVENUE);

      address revenueC = address(0xbeef99); // need new spigot for testing'
      address creditT = address(new RevenueToken());
      deal(creditT, address(dex), MAX_INT);


      bytes32 id = _createCredit(creditT, creditT, revenueC);
      _borrow(id, lentAmount);

      _createEthRevenue(revenueC, 100 ether);

      hoax(revenueC);
      (bool success, ) = payable(spigot).call{value: 100 ether}("");
      assertTrue(success);



      // anyone can claim revenue
      spigot.claimRevenue(revenueC, Denominations.ETH, "");

      uint claimable = spigot.getOwnerTokens(Denominations.ETH);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        Denominations.ETH,// tokenIn
        address(creditT), // tokenOut
        claimable, // amount in
        lentAmount // minAmountOut
      );
    
      hoax(arbiter);
      line.claimAndTrade(Denominations.ETH, tradeData); // claimToken (ETH), tradeData
      assertEq(line.unused(Denominations.ETH), 0); // used all unusedTokens[Eth]
    }
    function test_can_trade_and_repay(uint buyAmount, uint sellAmount, uint timespan) public {

      vm.assume(timespan < ttl);
      buyAmount = bound(buyAmount, 1, MAX_REVENUE);
      sellAmount = bound(sellAmount, 1, MAX_REVENUE);

      _borrow(line.ids(0), lentAmount);

      vm.warp(block.timestamp + timespan);
      line.accrueInterest();

      (,, uint interestAccrued,,,,,) = line.credits(line.ids(0));
      console.log("interestAccrued", interestAccrued);

      console.log("unused credit tokens before: ", line.unused(address(creditToken)));

      uint256 unusedCreditTokens = line.unused(address(creditToken));
      uint claimable = spigot.getOwnerTokens(address(revenueToken));
      uint256 tradable;
      uint256 expectedRevenueTokens;
      if ( sellAmount > claimable ) {
        // if the fuzzed sell amount is greater than the amount that's claimable, we won't be able to sell it
        tradable = claimable;
        expectedRevenueTokens = 0;
      } else {
        // expected difference will be claimable less sell amount
        tradable = sellAmount;
        expectedRevenueTokens = claimable - sellAmount; // ie whats left over after claiming
      }

      emit log_named_uint("claimable", claimable);
      emit log_named_uint("tradable", tradable);
      emit log_named_uint("expected", expectedRevenueTokens);
      
      // oracle prices not relevant to trading test
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        tradable,
        buyAmount
      );

      vm.prank(arbiter);
      uint256 tokensBought = line.claimAndRepay(address(revenueToken), tradeData);
      
      // principal, interest, repaid
      (,uint p, uint i, uint r,,,,) = line.credits(line.ids(0));

      if(interestAccrued > buyAmount) {
        // only interest paid
        assertEq(r, buyAmount, "r != buyAmount");            // paid what interest we could
        assertEq(i, interestAccrued - buyAmount, "i != interest - buyAmount"); // interest owed should be reduced by repay amount
        assertEq(p, lentAmount, "p != lentAmount");             // no change in principal
      } else {
        assertEq(p, buyAmount > lentAmount + interestAccrued ? 0 : lentAmount - (buyAmount - interestAccrued), "p, buyAmount > lentAmount + interest ? 0 : lentAmount - (buyAmount - interest)");
        assertEq(i, 0, "i != 0");                                   // all interest repaid
        assertEq(r, interestAccrued, "r != interestAccrued");              // all interest repaid

      }

      // check unused balances
      if (lentAmount + interestAccrued > buyAmount) {
        // if we buy less tokens than is needed to repay, then amount decreases (to 0), ie debt has not been repaid
        assertEq(p + i, lentAmount + interestAccrued - buyAmount, "post-claimAndRepay accounting does not add up");
        assertEq(line.unused(address(creditToken)), 0, "should have no unused credit tokens");
      } else {
        // debt has been repaid
        assertEq(p + i, 0, "principal and interest should be 0");
        assertEq(line.unused(address(creditToken)), unusedCreditTokens + tokensBought - lentAmount - interestAccrued, "unused credit tokens does not balance");
      }

      assertEq(line.unused(address(revenueToken)), expectedRevenueTokens, "unused revenue does not balance");
      
    }

    function _caclulateDiff(uint256 a, uint256 b) internal pure returns (int256) {
      uint256 diff;
      if (a > b) {
        diff = a - b;
        return (int256(diff) * -1);
      } else {
        diff = b - a;
        return int256(diff);
      }
    }

    function _simulateInitialClaimAndTradeForReserveChanges(uint256 creditTokensPurchased, uint256 claimableRevenue, uint256 revenue) internal {
      _borrow(line.ids(0), lentAmount);

      uint256 preBalance = line.unused(address(creditToken));
      assertEq(preBalance, 0, "prebalance should be 0");
      


      emit log_named_uint("revenue",revenue);

      // increase unusedTokens
      bytes memory tradeAndClaimData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        revenue, // claim tokens sent to dex
        creditTokensPurchased // target tokens received from dex
      );

      // claim token balance of the line contract before the trade
      uint256 oldClaimTokens = revenueToken.balanceOf(address(line));
       emit log_named_uint("oldClaimTokens",oldClaimTokens);

      // number of claim tokens remaining after the trade ( existing balance + amount claimed from spigot - amount sent to dex)
      uint256 newClaimTokens = oldClaimTokens + claimableRevenue - revenue;
      emit log_named_uint("newClaimTokens",newClaimTokens);

      // assertTrue(oldClaimTokens > newClaimTokens, "oldClaimTokens > newClaimTokens");
      // the difference between old claim (revenue) tokens and new claim (revenue) tokens
      int256 diff = _caclulateDiff(oldClaimTokens, newClaimTokens);

      emit log_named_int("diff",diff);
  
      vm.startPrank(arbiter);

      // SpigotedLineLib.claimAndTrade
      vm.expectEmit(true, true, true, true);
      emit ReservesChanged(address(revenueToken), diff, 0);

      // SpigotedLine.claimAndTrade
      vm.expectEmit(true, true, true, true);
      emit ReservesChanged(address(creditToken), int(creditTokensPurchased), 1);

      line.claimAndTrade(address(revenueToken), tradeAndClaimData);
      uint256 postBalance = line.unused(address(creditToken));
      assertEq(postBalance, creditTokensPurchased, "postBalance should equal creditsTokenPurchased");
      vm.stopPrank();

    }
  
      // use credit tokens already in reserve (-ve val, 1)
    function test_claimAndRepay_ReservedChanges_event_with_tokens_in_reserve(uint256 unusedTokens) public {
      unusedTokens = bound(unusedTokens, 2, 1_000_000 * 10**18);
      vm.assume(unusedTokens % 2 == 0);
      vm.assume(unusedTokens < type(uint256).max / 2);

      uint256 creditTokensPurchased = unusedTokens / 2;

      // because the MockZeroEx doesn't account for tokens in vs out, we need to "predict" the number of tokens sent (ie claimed + unused)
      uint256 claimableRevenue = spigot.getOwnerTokens(address(revenueToken));
      uint256 unusedClaimTokens = line.unused(address(revenueToken));
      uint256 revenue = (claimableRevenue + unusedClaimTokens) / 2;

      _simulateInitialClaimAndTradeForReserveChanges(creditTokensPurchased,claimableRevenue,revenue);
  
      // add more revenue to the spigot
      _generateRevenueAndClaim(1 ether);

      // claim and repay
      // in this scenario we want to use unused tokens from the reserve to repay
      creditTokensPurchased = 1;

      bytes memory tradeAndRepayData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        revenue / 2,
        creditTokensPurchased
      );

      // repaid = newTokens (bought from claimAndTrade) + unusedTokens[credit]
      // we want repaid > newTokens, ie existing balance of unused, which we have
      uint256 repaid = creditTokensPurchased + line.unused(address(creditToken));
      ( ,uint256 principal,uint256 interestAccrued , , , , , ) = line.credits(line.ids(0));
      uint256 debt = principal + interestAccrued;
      if (repaid > debt) repaid = debt;

      int256 diff = _caclulateDiff(repaid,creditTokensPurchased);
      assertTrue(diff < 0);

      vm.startPrank(arbiter);

      // SpigotedLineLib.claimAndRepay
      vm.expectEmit(true,false,true,true);
      emit ReservesChanged(address(revenueToken), 0, 0);

      // SpigotedLine.claimAndRepay
      vm.expectEmit(true, true, true, true);
      emit ReservesChanged(address(creditToken), diff, 1);
      line.claimAndRepay(address(revenueToken), tradeAndRepayData);
      vm.stopPrank();
    }



      // credit tokens get added to (excess) (+ve val, 1)
    function test_claimAndRepay_ReservedChanges_event_when_filling_reserves(uint256 unusedTokens) public {
      unusedTokens = bound(unusedTokens, 1, 1_000_000 * 10**18);
      vm.assume(unusedTokens % 2 == 0);
      vm.assume(unusedTokens < type(uint256).max / 2);

      console.log("dex revenue token balance beginning: ", revenueToken.balanceOf(address(dex)));

      uint256 creditTokensPurchased = 1;

      // because the MockZeroEx doesn't account for tokens in vs out, we need to "predict" the number of tokens sent (ie claimed + unused)
      uint256 claimableRevenue = spigot.getOwnerTokens(address(revenueToken));
      uint256 unusedClaimTokens = line.unused(address(revenueToken));
      uint256 revenue = (claimableRevenue + unusedClaimTokens) / 2;

      _simulateInitialClaimAndTradeForReserveChanges(creditTokensPurchased,claimableRevenue,revenue);
  
      // add more revenue to the spigot
      _generateRevenueAndClaim(1 ether);

      // claim and repay

      // in this scenario, we want debt < newTokens ( use all available DEX tokens)
      creditTokensPurchased = creditToken.balanceOf(address(dex));

      // repaid = newTokens (bought from claimAndTrade) + unusedTokens[credit]
      // we want repaid > newTokens, ie existing balance of unused, which we have
      uint256 repaid = creditTokensPurchased + line.unused(address(creditToken));
      ( ,uint256 principal,uint256 interestAccrued , , , , , ) = line.credits(line.ids(0));
      uint256 debt = principal + interestAccrued;
      if (repaid > debt) repaid = debt;
      emit log_named_uint("repaid", repaid);

      bytes memory tradeAndRepayData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        revenue / 2,
        creditTokensPurchased // this one
      );

      int256 diff = _caclulateDiff(repaid,creditTokensPurchased);
      assertTrue(diff > 0);
      emit log_named_int("diff", diff);

      vm.startPrank(arbiter);

      console.log("dex revenue token balance: ", revenueToken.balanceOf(address(dex)));

      // SpigotedLineLib.claimAndRepay
      vm.expectEmit(true,false,true,true);
      emit ReservesChanged(address(revenueToken), 0, 0);

      // SpigotedLine.claimAndRepay
      vm.expectEmit(true, true, true, true);
      emit ReservesChanged(address(creditToken), diff, 1);
      line.claimAndRepay(address(revenueToken), tradeAndRepayData);
      vm.stopPrank();
    }

    function test_useAndRepay_emits_ReservesChanged_event(uint256 unusedTokens) public {
      unusedTokens = bound(unusedTokens, 2, 1_000_000 * 10**18);
      vm.assume(unusedTokens % 2 == 0);
      vm.assume(unusedTokens < type(uint256).max / 2);

      uint256 creditTokensPurchased = unusedTokens;

      // because the MockZeroEx doesn't account for tokens in vs out, we need to "predict" the number of tokens sent (ie claimed + unused)
      uint256 claimableRevenue = spigot.getOwnerTokens(address(revenueToken));
      uint256 unusedClaimTokens = line.unused(address(revenueToken));
      uint256 revenue = (claimableRevenue + unusedClaimTokens) / 2;

      _simulateInitialClaimAndTradeForReserveChanges(creditTokensPurchased,claimableRevenue,revenue);

      ( ,uint256 principal,uint256 interestAccrued , , , , , ) = line.credits(line.ids(0));
      uint256 debt = principal + interestAccrued;

      vm.startPrank(borrower);

      uint256 payment = creditTokensPurchased < debt ? creditTokensPurchased : debt;
      
      vm.expectEmit(true, true, true, true);
      emit ReservesChanged(address(creditToken), -int256(payment), 0);
      line.useAndRepay(payment);
      vm.stopPrank();

    }

    function test_cannot_claim_and_repay_if_borrower(uint buyAmount, uint sellAmount, uint timespan) public {
      if(timespan > ttl) return;
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount >= MAX_REVENUE || sellAmount >= MAX_REVENUE) return;

      _borrow(line.ids(0), lentAmount);
      
      // no interest charged because no blocks processed
      uint256 interest = 0;

      // vm.warp(timespan);
      // line.accrueInterest();
      // (,,uint interest,,,,) = line.credits(line.ids(0)) ;

      // oracle prices not relevant to trading test
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        sellAmount,
        buyAmount
      );

      uint claimable = spigot.getOwnerTokens(address(revenueToken));

      vm.expectRevert(ISpigot.CallerAccessDenied.selector);
      vm.prank(borrower);
      console.log(buyAmount);
      console.log(sellAmount);
      line.claimAndRepay(address(revenueToken), tradeData);
    }

    function test_cannot_claim_and_repay_if_lender(uint buyAmount, uint sellAmount, uint timespan) public {
      if(timespan > ttl) return;
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount >= MAX_REVENUE || sellAmount >= MAX_REVENUE) return;

      _borrow(line.ids(0), lentAmount);
      
      // no interest charged because no blocks processed
      uint256 interest = 0;

      // vm.warp(timespan);
      // line.accrueInterest();
      // (,,uint interest,,,,) = line.credits(line.ids(0)) ;

      // oracle prices not relevant to trading test
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        sellAmount,
        buyAmount
      );

      uint claimable = spigot.getOwnerTokens(address(revenueToken));

      vm.expectRevert(ISpigot.CallerAccessDenied.selector);
      vm.prank(lender);
      console.log(buyAmount);
      console.log(sellAmount);
      line.claimAndRepay(address(revenueToken), tradeData);
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

    function test_cannot_depositAndRepay_when_sending_ETH() public {
      _borrow(line.ids(0), lentAmount);
      creditToken.mint(address(0xdebf), lentAmount);
      hoax(address(0xdebf));
      creditToken.approve(address(line), lentAmount);
      vm.expectRevert(LineLib.EthSentWithERC20.selector);
      line.depositAndRepay{value: 0.0000000098 ether}(lentAmount);
    }

    // Spigot integration tests
    // results change based on line status (ACTIVE vs LIQUIDATABLE vs INSOLVENT)
    // Only checking that Line functions dont fail. Check `Spigot.t.sol` for expected functionality

    // releaseSpigot()

    function test_release_spigot_while_active() public {
      vm.startPrank(arbiter);
      vm.expectRevert(ISpigot.CallerAccessDenied.selector);
      assertFalse(line.releaseSpigot(arbiter));
    }

    function test_release_spigot_to_borrower_when_repaid() public {  
      vm.startPrank(borrower);
      line.close(line.ids(0));
      vm.stopPrank();

      hoax(borrower);
      assertTrue(line.releaseSpigot(borrower));

      assertEq(spigot.owner(), borrower);
    }

    function test_cannot_close_with_ETH() public {
      vm.startPrank(borrower);
        bytes32 id = line.ids(0);
        vm.expectRevert(LineLib.EthSentWithERC20.selector);
        line.close{value: 0.00001 ether}(id);
      vm.stopPrank();
    }

    function test_only_borrower_release_spigot_when_repaid() public {  
      vm.startPrank(borrower);
      line.close(line.ids(0));
      vm.stopPrank();

      vm.expectRevert(ISpigot.CallerAccessDenied.selector);
      line.releaseSpigot(borrower);
    }

    function test_release_spigot_to_arbiter_when_liquidated() public {  
      vm.warp(ttl+1);

      assertTrue(line.releaseSpigot(arbiter));

      assertEq(spigot.owner(), arbiter);
    }


    function test_only_arbiter_release_spigot_when_liquidated() public {  
      vm.warp(ttl+1);

      hoax(lender);
      vm.expectRevert(ISpigot.CallerAccessDenied.selector);
      line.releaseSpigot(arbiter);
    }
    // sweep()



    function test_cant_sweep_tokens_while_active() public {
      _borrow(line.ids(0), lentAmount);
      uint claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amountd tokens for test
      // create unused tokens      
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount
      );
      hoax(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);
      vm.stopPrank();

      vm.expectRevert(ISpigot.CallerAccessDenied.selector);
      assertEq(0, line.sweep(address(this), address(creditToken), 0)); // no tokens transfered
    }


    function test_can_sweep_empty_tokens() public {
      // sweeps 0 so no side effects but tx succeeds
      uint256 preBalance = line.unused(address(creditToken));
      emit log_named_uint("unused", preBalance);
      vm.warp(ttl+2);
      hoax(arbiter);
      uint256 swept = line.sweep(address(this), address(creditToken), 0);
      assertEq(swept, 0);
      uint256 postBalance = line.unused(address(creditToken));
      assertEq(preBalance, 0, "prebalance should be 0");
      assertEq(postBalance, 0, "post balance should be 0");
    }

    function test_can_perform_partial_sweep_of_unused_tokens(uint256 unusedTokens) public {
      unusedTokens = bound(unusedTokens, 1, 1_000_000 * 10**18);
      vm.assume(unusedTokens % 2 == 0);

      _borrow(line.ids(0), lentAmount);

      uint256 preBalance = line.unused(address(creditToken));
      assertEq(preBalance, 0, "prebalance should be 0");
      uint256 claimable = spigot.getOwnerTokens(address(creditToken));
      emit log_named_uint("claimable", claimable);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable,
        unusedTokens
      );
      vm.startPrank(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);
      uint256 postBalance = line.unused(address(creditToken));
      assertEq(postBalance, unusedTokens);

      vm.warp(ttl+2);

      uint256 swept = line.sweep(address(this), address(creditToken), unusedTokens/2);
      assertEq(swept, unusedTokens/2);
      postBalance = line.unused(address(creditToken));
      assertEq(postBalance, unusedTokens/2);

      swept = line.sweep(address(this), address(creditToken), unusedTokens/2);
      assertEq(swept, unusedTokens/2);
      postBalance = line.unused(address(creditToken));
      assertEq(postBalance, 0);
      vm.stopPrank();
    }

    function test_can_sweep_max_amount_of_unused_tokens_by_passing_zero_amount(uint256 unusedTokens) public {
      unusedTokens = bound(unusedTokens, 1, 1_000_000 * 10**18);
      
      _borrow(line.ids(0), lentAmount);

      uint256 preBalance = line.unused(address(creditToken));
      assertEq(preBalance, 0, "prebalance should be 0");
      uint256 claimable = spigot.getOwnerTokens(address(creditToken));
      emit log_named_uint("claimable", claimable);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable,
        unusedTokens
      );
      vm.startPrank(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);
      uint256 postBalance = line.unused(address(creditToken));
      assertEq(postBalance, unusedTokens);

      vm.warp(ttl+2);

      uint256 swept = line.sweep(address(this), address(creditToken), 0);
      assertEq(swept, unusedTokens);
      postBalance = line.unused(address(creditToken));
      assertEq(postBalance, 0);
      vm.stopPrank();
    }

    function test_cannot_sweep_more_than_unused_tokens(uint256 unusedTokens) public {
      unusedTokens = bound(unusedTokens, 1, 1_000_000 * 10**18);

      _borrow(line.ids(0), lentAmount);

      uint256 preBalance = line.unused(address(creditToken));
      assertEq(preBalance, 0, "prebalance should be 0");
      
      uint256 claimable = spigot.getOwnerTokens(address(creditToken));

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimable,
        unusedTokens
      );
      vm.startPrank(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);
      uint256 postBalance = line.unused(address(creditToken));
      assertEq(postBalance, unusedTokens);

      vm.warp(ttl+2);

      vm.expectRevert(abi.encodeWithSelector(ISpigotedLine.ReservesOverdrawn.selector, address(creditToken), unusedTokens));
      line.sweep(address(this), address(creditToken), unusedTokens+1);
      vm.stopPrank();
    }

    function test_cant_sweep_tokens_when_repaid_as_anon() public {
      _borrow(line.ids(0), lentAmount);
      uint claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amountd tokens for test
      // create unused tokens      
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount + 1 ether // give excess tokens so we can sweep with out UsedExcess error
      );
      
      hoax(arbiter);
      line.claimAndRepay(address(revenueToken), tradeData);
      bytes32 id = line.ids(0);
      hoax(borrower);
      line.close(id);
      assertEq(uint(line.status()), uint(LineLib.STATUS.REPAID));

      hoax(address(0xdebf));
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      assertEq(0, line.sweep(address(this), address(creditToken), 0)); // no tokens transfered
    }

    function test_sweep_to_borrower_when_repaid() public {
      _borrow(line.ids(0), lentAmount);

      uint claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amount
      console.log(claimed);
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 10,
        lentAmount + 1 ether // give excess tokens so we can sweep with out UsedExcess error
      );

      vm.prank(arbiter);
      line.claimAndRepay(address(revenueToken), tradeData);
      
      bytes32 id = line.ids(0);
      hoax(borrower);
      line.close(id);

      // initial mint + spigot revenue to borrower (- unused?)
      uint balance = revenueToken.balanceOf(address(borrower));
      console.log(balance);
      console.log(MAX_REVENUE);
      assertEq(balance, MAX_REVENUE, '1'); // tbh idk y its +1 here

      // The above assert is causing issues, not really sure what its supposed to be doing


      uint unused = line.unused(address(revenueToken)); 
      hoax(borrower);
      uint swept = line.sweep(address(borrower), address(revenueToken), 0);

      assertEq(unused, 10, '2');     // all unused sent to arbi
      assertEq(swept, unused, '3'); // all unused sent to arbi
      assertEq(swept, 10, '4');      // untraded revenue
      assertEq(swept, revenueToken.balanceOf(address(borrower)) - balance, '5'); // arbi balance updates properly
    }

    function test_cant_sweep_tokens_when_liquidate_as_anon() public {
      _borrow(line.ids(0), lentAmount);
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        MAX_REVENUE / 100,
        lentAmount // give excess tokens so we can sweep with out UsedExcess error
      );

      hoax(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);

      vm.warp(ttl+1);

      hoax(address(0xdebf));
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      assertEq(0, line.sweep(address(this), address(creditToken), 0)); // no tokens transfered
    }



    function test_sweep_to_arbiter_when_liquidated() public {
      _borrow(line.ids(0), lentAmount);

      uint claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amount 

      hoax(arbiter);
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount
      );
      line.claimAndRepay(address(revenueToken), tradeData); 
      vm.stopPrank();

      assertEq(uint(line.status()), uint(LineLib.STATUS.ACTIVE));

      uint balance = revenueToken.balanceOf(address(arbiter));
      uint unused = line.unused(address(revenueToken));

      vm.warp(ttl+1);          // set to liquidatable
      
      uint swept = line.sweep(address(this), address(revenueToken), 0);
      assertEq(swept, unused); // all unused sent to arbiter
      assertEq(swept, 1);      // untraded revenue
      assertEq(swept, revenueToken.balanceOf(address(arbiter)) - balance); // arbiter balance updates properly
    }

    function test_arbiter_sweep_if_status_liquidatable() public {
      uint claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amount

      _borrow(line.ids(0), lentAmount);

      hoax(arbiter);
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount + 1 ether // give excess tokens so we can sweep with out UsedExcess error
      );
     
      line.claimAndTrade(address(revenueToken), tradeData);
     
      vm.warp(ttl+1);
      vm.startPrank(arbiter);
      line.sweep(arbiter, address(creditToken), 0);
    }

    function test_arbiter_sweep_if_status_insolvent() public {
      uint claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amount

      _borrow(line.ids(0), lentAmount);

      hoax(arbiter);
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount + 1 ether // give excess tokens so we can sweep with out UsedExcess error
      );
     
      line.claimAndTrade(address(revenueToken), tradeData);
      vm.warp(ttl+1);

      line.releaseSpigot(arbiter);
      
      vm.startPrank(arbiter);
      spigot.updateOwner(address(30));
      line.declareInsolvent();
      
      assertEq(uint8(line.status()), uint8(LineLib.STATUS.INSOLVENT));
      
      line.sweep(arbiter, address(creditToken), 0);
      
    }

    function test_new_owner_when_spigot_released() public {
          uint claimed = (MAX_REVENUE * ownerSplit) / 100; // expected claim amount

      _borrow(line.ids(0), lentAmount);

      hoax(arbiter);
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount + 1 ether // give excess tokens so we can sweep with out UsedExcess error
      );
     
      line.claimAndTrade(address(revenueToken), tradeData);
      vm.warp(ttl+1);

      line.releaseSpigot(arbiter);
      
      vm.startPrank(arbiter);

      address new_owner = address(30);
      spigot.updateOwner(new_owner);

      assertEq(spigot.owner(), new_owner);

    }

    // updateOwnerSplit()

    function test_split_must_be_lte_100(uint8 proposedSplit) public {
      if(proposedSplit > 100) {
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
      (uint8 split,,) = spigot.getSetting(revenueContract);
      assertEq(split, ownerSplit);
      
      // fast forward to past deadline
      vm.warp(ttl+1);

      assertTrue(line.updateOwnerSplit(revenueContract));
      (uint8 split2,,) = spigot.getSetting(revenueContract);
      assertEq(split2, 100); // to 100 since LIQUIDATABLE

      // second run shouldnt updte
      assertFalse(line.updateOwnerSplit(revenueContract));
      // split should still be 100%
      (uint8 split3,,) = spigot.getSetting(revenueContract);
      assertEq(split3, 100);
    }

    function test_update_split_bad_contract() public {
      vm.expectRevert(SpigotedLineLib.NoSpigot.selector);
      line.updateOwnerSplit(address(0xdead));
    }

    function test_update_split_to_100_on_liquidate() public {
      // fast forward to past deadline
      vm.warp(ttl+1);

      assertTrue(line.updateOwnerSplit(revenueContract));
      assertEq(uint(line.status()), uint(LineLib.STATUS.LIQUIDATABLE));
      (uint8 split,,) = spigot.getSetting(revenueContract);
      assertEq(split, 100);
    }

    function test_update_split_to_default_on_active_from_liquidate() public {
      // validate original settings
      (uint8 split,,) = spigot.getSetting(revenueContract);
      assertEq(split, ownerSplit);
      
      // fast forward to past deadline
      vm.warp(ttl+1);

      assertTrue(line.updateOwnerSplit(revenueContract));
      assertEq(uint(line.status()), uint(LineLib.STATUS.LIQUIDATABLE));
      (uint8 split2,,) = spigot.getSetting(revenueContract);
      assertEq(split2, 100); // to 100 since LIQUIDATABLE

      vm.warp(1);            // sstatus = LIQUIDTABLE but healthcheck == ACTIVE
      assertTrue(line.updateOwnerSplit(revenueContract));
      (uint8 split3,,) = spigot.getSetting(revenueContract);
      assertEq(split3, ownerSplit); // to default since ACTIVE
    }

    // addSpigot()

    function test_cant_add_spigot_without_consent() public {
      address rev = address(0xf1c0);
      ISpigot.Setting memory setting = ISpigot.Setting({
        ownerSplit: ownerSplit,
        claimFunction: bytes4(0),
        transferOwnerFunction: bytes4("1234")
      });

      hoax(lender);
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.addSpigot(rev, setting);
    }

    function test_can_add_spigot_with_consent() public {
      address rev = address(0xf1c0);
      ISpigot.Setting memory setting = ISpigot.Setting({
        ownerSplit: ownerSplit,
        claimFunction: bytes4(0),
        transferOwnerFunction: bytes4("1234")
      });

      // hoax(arbiter);
      line.addSpigot(rev, setting);

      (uint8 split,bytes4 claim,bytes4 transfer) = spigot.getSetting(rev);
      // settings not saved on spigot contract
      assertEq(transfer, setting.transferOwnerFunction);
      assertEq(claim, setting.claimFunction);
      assertEq(split, setting.ownerSplit);
    }

    // updateWhitelist
    function test_cant_whitelist_as_anon() public {
      hoax(address(0xdebf));
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.updateWhitelist(bytes4("0000"), true);
    }

    function test_cant_whitelist_as_borrower() public {
      hoax(borrower);
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.updateWhitelist(bytes4("0000"), true);
    }

    function test_can_whitelist_as_arbiter() public {
      assertTrue(line.updateWhitelist(bytes4("0000"), true));
    }

    function test_cant_use_and_repay_if_unauthorized() public {
      _borrow(line.ids(0), lentAmount);
      
      // random user
      vm.prank(makeAddr("alice"));
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.useAndRepay(1);
      
      // arbiter can't useAndRepay
      vm.prank(arbiter);
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.useAndRepay(1);
    }
    
    
    function test_lender_can_use_and_repay() public {
      deal(address(lender), lentAmount + 1 ether);
      deal(address(revenueToken), MAX_REVENUE);
      address revenueC = address(0xbeef); // need new spigot for testing
      bytes32 id = _createCredit(address(revenueToken), address(revenueToken), revenueC);
      _borrow(id, lentAmount);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken), // token in
        Denominations.ETH, // token out
        1 gwei, //amountIn
        lentAmount // minAmountOut
      );

      hoax(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);


      (, uint256 principal,uint256 interest,,,,,) = line.credits(line.ids(0));
      vm.prank(lender); // prank lender
      line.useAndRepay(principal + interest);
      (, principal,,,,,,) = line.credits(line.ids(0));
      assertEq(principal, 0, "principal should be zero");
    }
    
    function test_cant_claim_and_repay_if_unauthorized() public {
      _borrow(line.ids(0), lentAmount);
      
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        lentAmount,
        lentAmount
      );

      // random user
      vm.prank(makeAddr("alice"));
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.claimAndRepay(address(revenueToken), tradeData);
      
      // borrower can't claim and repay
      vm.prank(borrower);
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.claimAndRepay(address(revenueToken), tradeData);

      // lender can't claim and repay
      vm.prank(lender);
      vm.expectRevert(ILineOfCredit.CallerAccessDenied.selector);
      line.claimAndRepay(address(revenueToken), tradeData);
    }
    
    function test_arbiter_can_claim_and_repay() public {
      _borrow(line.ids(0), lentAmount);
      
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        lentAmount,
        lentAmount
      );

      vm.prank(arbiter);
      line.claimAndRepay(address(revenueToken), tradeData);
    }

    // tests that the amount used to repay the lender cannot cause an underflow
    function test_lender_use_and_repay_underflow() public {
      uint256 largeRevenueAmount = lentAmount * 2;

      deal(address(lender), lentAmount + 1 ether);
      deal(address(revenueToken), MAX_REVENUE);
      // address revenueC = address(0xbeef); // need new spigot for testing
      // bytes32 id = _createCredit(address(revenueToken), address(creditToken), revenueC);
      bytes32 id = line.ids(0);

      // 1. Borrow lentAmount = 1 ether
      _borrow(id, lentAmount);

      // 2. Claim and trade largeRevenueAmount = 2 ether (revenue)
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        1 gwei,
        largeRevenueAmount
      );

      hoax(arbiter);
      line.claimAndTrade(address(revenueToken), tradeData);

      (, uint256 principalBeforeRepaying,,,,,,) = line.credits(line.ids(0));
      assertEq(principalBeforeRepaying, lentAmount);

      // 3. Use and repay debt with previously claimed and traded revenue (largeRevenueAmount = 2 ether)
      vm.startPrank(lender);
      
      vm.expectRevert(
        abi.encodeWithSelector(
         ILineOfCredit.RepayAmountExceedsDebt.selector,
         principalBeforeRepaying
        )
      );

      line.useAndRepay(largeRevenueAmount);
    }

}

