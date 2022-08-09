
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import { RevenueToken } from "../../mock/RevenueToken.sol";
import { SimpleOracle } from "../../mock/SimpleOracle.sol";
import { ZeroEx } from "../../mock/ZeroEx.sol";

import { Spigot } from "../spigot/Spigot.sol";
import { SpigotedLoan } from './SpigotedLoan.sol';
import { LoanLib } from '../../utils/LoanLib.sol';
import { ISpigot } from '../../interfaces/ISpigot.sol';
import { ISpigotedLoan } from '../../interfaces/ISpigotedLoan.sol';
import { ILineOfCredit } from '../../interfaces/ILineOfCredit.sol';

/**
 * @notice
 * @dev - does not test spigot integration e.g. claimEscrow() since that should already be covered in Spigot tests
 *      - these tests would fail if that assumption was wrong anyway
 */
contract SpigotedLoanTest is Test {
    ZeroEx dex;
    SpigotedLoan loan;
    Spigot spigot;

    RevenueToken creditToken;
    RevenueToken revenueToken;

    // Named vars for common inputs
    address constant eth = address(0);
    address constant revenueContract = address(0xdebf);
    uint lentAmount = 1 ether;
    
    uint128 constant drawnRate = 100;
    uint128 constant facilityRate = 1;
    uint constant ttl = 10 days; // allows us t
    uint8 constant ownerSplit = 10; // 10% of all borrower revenue goes to spigot

    uint constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint constant MAX_REVENUE = MAX_INT / 100;

    // Loan access control vars
    address private arbiter = address(this);
    address private borrower = address(1);
    address private lender = address(2);
    SimpleOracle private oracle;

    function setUp() public {
        dex = new ZeroEx();
        creditToken = new RevenueToken();
        revenueToken = new RevenueToken();

        oracle = new SimpleOracle(address(revenueToken), address(creditToken));
        loan = new SpigotedLoan(address(oracle), arbiter, borrower, address(dex), ttl, ownerSplit);
        spigot = loan.spigot();

        _mintAndApprove();
        
        _createCredit();
        // revenue go brrrrrrr
        spigot.claimRevenue(address(revenueContract), "");
    }

    function _createCredit() public returns(bytes32 id) {
      ISpigot.Setting memory setting = ISpigot.Setting({
        token: address(revenueToken),
        ownerSplit: ownerSplit,
        claimFunction: bytes4(0),
        transferOwnerFunction: bytes4("1234")
      });

      startHoax(borrower);
      creditToken.approve(address(loan), MAX_INT);
      loan.addCredit(drawnRate, facilityRate, lentAmount, address(creditToken), lender);
      loan.addSpigot(revenueContract, setting);
      vm.stopPrank();
      
      startHoax(lender);
      creditToken.approve(address(loan), MAX_INT);
      id = loan.addCredit(drawnRate, facilityRate, lentAmount, address(creditToken), lender);
      vm.stopPrank();

      loan.addSpigot(revenueContract, setting);
    }

    function _borrow() public {
      vm.startPrank(borrower);
      loan.borrow(loan.ids(0), lentAmount);
      vm.stopPrank();
    }

    function _mintAndApprove() public {
      
      // seed dex with tokens to buy
      creditToken.mint(address(dex), MAX_REVENUE);
      // allow loan to use tokens for depositAndRepay()
      creditToken.mint(lender, MAX_REVENUE);
      creditToken.mint(address(this), MAX_REVENUE);
      creditToken.approve(address(loan), MAX_INT);
      // allow trades
      creditToken.approve(address(dex), MAX_INT);
      

      // tokens to trade

      revenueToken.mint(borrower, MAX_REVENUE);
      revenueToken.mint(address(loan), MAX_REVENUE);
      revenueToken.mint(address(dex), MAX_REVENUE);
      revenueToken.mint(address(this), MAX_REVENUE);
      revenueToken.approve(address(dex), MAX_INT);

      // revenue earned
      revenueToken.mint(address(spigot), MAX_REVENUE);
      // allow deposits
      revenueToken.approve(address(loan), MAX_INT);
    }


    // claimAndTrade 
    
    // TODO add raw ETH tests

  
    function test_can_trade(uint buyAmount, uint sellAmount) public {
      // oracle prices not relevant to test
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      
      vm.startPrank(borrower);
      // need to have active position so we can buy asset
      loan.borrow(loan.ids(0), buyAmount);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        sellAmount,
        buyAmount
      );

      uint claimable = spigot.getEscrowed(address(revenueToken));

      loan.claimAndTrade(address(revenueToken), tradeData);

      vm.stopPrank();
      
      // dex balances
      assertEq(creditToken.balanceOf((address(dex))), MAX_REVENUE - buyAmount);
      assertEq(revenueToken.balanceOf((address(dex))), MAX_REVENUE + sellAmount);
      
      // loan balances
      assertEq(creditToken.balanceOf((address(loan))), lentAmount + buyAmount); // TODO cwalk help
      assertEq(revenueToken.balanceOf((address(loan))), MAX_REVENUE + claimable - sellAmount);
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
      loan.claimAndTrade(address(revenueToken), tradeData);
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
      loan.claimAndRepay(address(revenueToken), tradeData);
    }

    function test_can_trade_and_repay(uint buyAmount, uint sellAmount) public {
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      
      vm.startPrank(borrower);
      loan.borrow(loan.ids(0), lentAmount);
      
      // no interest charged because no blocks processed
      uint256 interest = 0;

      // oracle prices not relevant to trading test
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        sellAmount,
        buyAmount
      );

      uint claimable = spigot.getEscrowed(address(revenueToken));

      loan.claimAndRepay(address(revenueToken), tradeData);
      vm.stopPrank();

      // principal, interest, repaid
      (,uint p, uint i, uint r,,,) = loan.credits(loan.ids(0));

      // outstanding credit = initial principal + accrued interest - tokens repaid
      assertEq(p + i, lentAmount + interest - buyAmount);

      if(interest > buyAmount) {
        // only interest paid
        assertEq(r, buyAmount); // paid what interest we could
        assertEq(i, interest - buyAmount); // interest owed should be reduced by repay amount
        assertEq(p, lentAmount); // no change in principal

      } else {
        assertEq(p, lentAmount - (buyAmount - interest));
        // all interest repaid
        assertEq(i, 0);
        assertEq(r, interest);

      }
      emit log_named_uint("----  BUY AMOUNT ----", buyAmount);
      emit log_named_uint("----  SELL AMOUNT ----", sellAmount);

      uint unusedCreditToken =  buyAmount < lentAmount ? 0 : buyAmount - lentAmount;
      assertEq(loan.unused(address(creditToken)), unusedCreditToken);
      assertEq(loan.unused(address(revenueToken)), MAX_REVENUE + claimable - sellAmount);
    }
    
    // write tests for unused tokens

    function test_anyone_can_deposit_and_repay() public {
      _borrow();

      creditToken.mint(address(0xdebf), lentAmount);
      hoax(address(0xdebf));
      creditToken.approve(address(loan), lentAmount);
      loan.depositAndRepay(lentAmount);
    }

    // Spigot integration tests
    // results change based on loan status (ACTIVE vs LIQUIDATABLE vs INSOLVENT)
    // Only checking that Loan functions dont fail. Check `Spigot.t.sol` for expected functionality


    // releaseSpigot()

    function test_release_spigot_while_active() public {
      assertFalse(loan.releaseSpigot());
    }

    function test_release_spigot_to_borrower_when_repaid() public {  
      vm.startPrank(borrower);
      loan.close(loan.ids(0));
      vm.stopPrank();

      assertTrue(loan.releaseSpigot());

      assertEq(spigot.owner(), borrower);
    }

    function test_release_spigot_to_arbiter_when_liquidated() public {  
      vm.warp(ttl+1);

      assertTrue(loan.releaseSpigot());

      assertEq(spigot.owner(), arbiter);
    }

    // sweep()

    function test_cant_sweep_tokens_while_active() public {
      _borrow();
      hoax(borrower);
      uint claimed = MAX_REVENUE / ownerSplit; // expected claim amountd tokens for test
      // create unused tokens      
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount
      );
      loan.claimAndRepay(address(revenueToken), tradeData);
      vm.stopPrank();
      assertEq(0, loan.sweep(address(creditToken))); // no tokens transfered
    }

    function test_sweep_to_borrower_when_repaid() public {
      _borrow();
      hoax(borrower);

      uint claimed = MAX_REVENUE / ownerSplit; // expected claim amount
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount
      );
      loan.claimAndRepay(address(revenueToken), tradeData);
      vm.stopPrank();

      // initial mint + spigot revenue to borrower - unused
      assertEq((MAX_REVENUE * 2) - 1, revenueToken.balanceOf(address(borrower)));


      uint balance = revenueToken.balanceOf(address(borrower));

      uint unused = loan.unused(address(revenueToken));
      uint swept = loan.sweep(address(revenueToken));

      assertEq(unused, 1); // all unused sent to arbi
      assertEq(swept, unused); // all unused sent to arbi
      assertEq(swept, 1);      // untraded revenue
      assertEq(swept, revenueToken.balanceOf(address(borrower)) - balance); // arbi balance updates properly
    }

    function test_sweep_to_arbiter_when_liquidated() public {
      _borrow();

      uint claimed = MAX_REVENUE / ownerSplit; // expected claim amount 

      hoax(borrower);
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        claimed - 1,
        lentAmount
      );
      loan.claimAndRepay(address(revenueToken), tradeData); 
      vm.stopPrank();

      assertEq(uint(loan.loanStatus()), uint(LoanLib.STATUS.REPAID));

      uint balance = revenueToken.balanceOf(address(arbiter));
      uint unused = loan.unused(address(revenueToken));

      vm.warp(ttl+1);          // set to liquidatable
      
      uint swept = loan.sweep(address(revenueToken));
      assertEq(swept, unused); // all unused sent to arbi
      assertEq(swept, 1);      // untraded revenue
      assertEq(swept, revenueToken.balanceOf(address(arbiter)) - balance); // arbi balance updates properly
    }

    // updateOwnerSplit()

    function test_update_split_no_action_on_active() public {
      // already at default so doesnt change
      assertFalse(loan.updateOwnerSplit(revenueContract));
    }

    function test_update_split_no_action_on_already_liquidated() public {
      // validate original settings
      (,uint8 split,,) = spigot.getSetting(revenueContract);
      assertEq(split, ownerSplit);
      
      // fast forward to past deadline
      vm.warp(ttl+1);

      assertTrue(loan.updateOwnerSplit(revenueContract));
      (,uint8 split2,,) = spigot.getSetting(revenueContract);
      assertEq(split2, 100); // to 100 since LIQUIDATABLE

      // second run shouldnt updte
      assertFalse(loan.updateOwnerSplit(revenueContract));
      // split should still be 100%
      (,uint8 split3,,) = spigot.getSetting(revenueContract);
      assertEq(split3, 100);
    }

    function test_update_split_bad_contract() public {
      vm.expectRevert(ISpigotedLoan.NoSpigot.selector);
      loan.updateOwnerSplit(address(0xdead));
    }

    function test_update_split_to_100_on_liquidate() public {
      // fast forward to past deadline
      vm.warp(ttl+1);

      assertTrue(loan.updateOwnerSplit(revenueContract));
      assertEq(uint(loan.loanStatus()), uint(LoanLib.STATUS.LIQUIDATABLE));
      (,uint8 split,,) = spigot.getSetting(revenueContract);
      assertEq(split, 100);
    }

    function test_update_split_to_default_on_active_from_liquidate() public {
      // validate original settings
      (,uint8 split,,) = spigot.getSetting(revenueContract);
      assertEq(split, ownerSplit);
      
      // fast forward to past deadline
      vm.warp(ttl+1);

      assertTrue(loan.updateOwnerSplit(revenueContract));
      assertEq(uint(loan.loanStatus()), uint(LoanLib.STATUS.LIQUIDATABLE));
      (,uint8 split2,,) = spigot.getSetting(revenueContract);
      assertEq(split2, 100); // to 100 since LIQUIDATABLE

      vm.warp(1);            // sloanStatus = LIQUIDTABLE but healthcheck == ACTIVE
      assertTrue(loan.updateOwnerSplit(revenueContract));
      (,uint8 split3,,) = spigot.getSetting(revenueContract);
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

      loan.addSpigot(rev, setting);
      (address token,,,bytes4 transferFunc) = spigot.getSetting(rev);
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

      loan.addSpigot(rev, setting);
      hoax(borrower);
      loan.addSpigot(rev, setting);

      (address token,uint8 split,bytes4 claim,bytes4 transfer) = spigot.getSetting(rev);
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
      loan.updateWhitelist(bytes4("0000"), true);
    }

    function test_cant_whitelist_as_borrower() public {
      hoax(borrower);
      vm.expectRevert();
      loan.updateWhitelist(bytes4("0000"), true);
    }

    function test_can_whitelist_as_arbiter() public {
      assertTrue(loan.updateWhitelist(bytes4("0000"), true));
    }
}

