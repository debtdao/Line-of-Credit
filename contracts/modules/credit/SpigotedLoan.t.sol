
pragma solidity ^0.8.9;

import { DSTest } from  "../../../lib/ds-test/src/test.sol";
import { RevenueToken } from "../../mock/RevenueToken.sol";
import { SimpleOracle } from "../../mock/SimpleOracle.sol";
import { ZeroEx } from "../../mock/ZeroEx.sol";

import { Spigot } from "../spigot/Spigot.sol";
import { SpigotedLoan } from './SpigotedLoan.sol';
import { LoanLib } from '../../utils/LoanLib.sol';
import { ISpigot } from '../../interfaces/ISpigot.sol';

/**
 * @notice
 * @dev - does not test spigot integration e.g. claimEscrow() since that should already be covered in Spigot tests
 *      - these tests would fail if that assumption was wrong anyway
 */
contract SpigotedLoanTest is DSTest {
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
    address private lender;
    SimpleOracle private oracle;
    address private arbiter;
    address private borrower;

    function setUp() public {
        lender = address(this);
        arbiter = address(this);
        borrower = address(this);
        dex = new ZeroEx();
        creditToken = new RevenueToken();
        revenueToken = new RevenueToken();

        oracle = new SimpleOracle(address(revenueToken), address(creditToken));
        spigot = new Spigot(address(this), borrower, borrower);
        
        loan = new SpigotedLoan(address(oracle), arbiter, borrower, address(spigot), address(dex), ttl, ownerSplit);
        
        spigot.updateOwner(address(loan));

        loan.init();

        _mintAndApprove();
        
        // take out loan
        loan.addCredit(drawnRate, facilityRate, lentAmount, address(creditToken), lender);
        loan.addCredit(drawnRate, facilityRate, lentAmount, address(creditToken), lender);

        ISpigot.Setting memory setting = ISpigot.Setting({
          token: address(revenueToken),
          ownerSplit: ownerSplit,
          claimFunction: bytes4(0),
          transferOwnerFunction: bytes4("1234")
        });
        loan.addSpigot(revenueContract, setting);
        loan.addSpigot(revenueContract, setting);

        // revenue go brrrrrrr
        spigot.claimRevenue(address(revenueContract), "");
    }

    function _mintAndApprove() public {
      
      // seed dex with tokens to buy
      creditToken.mint(address(dex), MAX_REVENUE);
      // allow loan to use tokens for depositAndRepay()
      creditToken.mint(address(this), MAX_REVENUE);
      creditToken.approve(address(loan), MAX_INT);
      // allow trades
      creditToken.approve(address(dex), MAX_INT);
      

      // tokens to trade

      revenueToken.mint(address(this), MAX_REVENUE);
      revenueToken.mint(address(loan), MAX_REVENUE);
      revenueToken.mint(address(dex), MAX_REVENUE);
      revenueToken.approve(address(dex), MAX_INT);

      // revenue earned
      revenueToken.mint(address(spigot), MAX_REVENUE);
      // allow deposits
      revenueToken.approve(address(loan), MAX_INT);

    }

    // TODO can only remove spigot if repaid or insolvent (propery access for both situations)
    function testFail_trade_when_no_credit() public {
      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        1,
        1
      );

      loan.claimAndTrade(address(revenueToken), tradeData);
    }

    // trades work
    function test_can_trade(uint buyAmount, uint sellAmount) public {
      // oracle prices not relevant to test
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;
      
      // need to have active position so we can buy asset
      loan.borrow(loan.ids(0), buyAmount);

      bytes memory tradeData = abi.encodeWithSignature(
        'trade(address,address,uint256,uint256)',
        address(revenueToken),
        address(creditToken),
        sellAmount,
        buyAmount
      );

      uint claimable = spigot.getEscrowBalance(address(revenueToken));

      loan.claimAndTrade(address(revenueToken), tradeData);
      
      // dex balances
      assertEq(creditToken.balanceOf((address(dex))), MAX_REVENUE - buyAmount);
      assertEq(revenueToken.balanceOf((address(dex))), MAX_REVENUE + sellAmount);
      
      // loan balances
      assertEq(creditToken.balanceOf((address(loan))), lentAmount + buyAmount); // TODO cwalk help
      assertEq(revenueToken.balanceOf((address(loan))), MAX_REVENUE + claimable - sellAmount);
    }

    function test_can_trade_and_repay(uint buyAmount, uint sellAmount) public {
      if(buyAmount == 0 || sellAmount == 0) return;
      if(buyAmount > MAX_REVENUE || sellAmount > MAX_REVENUE) return;

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

      uint claimable = spigot.getEscrowBalance(address(revenueToken));

      loan.claimAndRepay(address(revenueToken), tradeData);

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

    // check unsused balances. Do so by changing minAmountOut in trade 0

    // Spigot integration tests
    // Only checking that Loan functions dont fail. Check `Spigot.t.sol` for expected functionality

    function test_can_deposit_and_repay() public {
      loan.borrow(loan.ids(0), lentAmount);
      loan.depositAndRepay(lentAmount);
    }

    function test_update_split() public {
      loan.updateOwnerSplit(revenueContract);
    }

    function testFail_release_spigot_while_active() public {
      assertTrue(loan.releaseSpigot());
    }

    function test_release_spigot_when_repaid() public {
      loan.close(loan.ids(0));
      assertTrue(loan.releaseSpigot());

      // TODO: bad test, will be address(this either way
      assertEq(spigot.owner(), borrower);
    }

    function test_cant_sweep_tokens_while_active() public {
      assertEq(0, loan.sweep(address(creditToken))); // no tokens transfered
    }

    function test_sweep_tokens_when_repaid() public {
      assertTrue(loan.close(loan.ids(0)));
      uint unused = loan.unused(address(creditToken));
      assertEq(loan.sweep(address(creditToken)), unused);
    }

    function testFail_update_split_bad_contract() public {
      loan.updateOwnerSplit(address(0xdead));
    }

    // TODO force loan into liquidatable to test - updateOwnerSplit, sweep, and releaseSpigot
}
