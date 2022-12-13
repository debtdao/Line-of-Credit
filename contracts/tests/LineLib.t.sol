pragma solidity 0.8.9;


import "forge-std/Test.sol";

import { Denominations } from "chainlink/Denominations.sol";

import { MockReceivables, MockStatefulReceivables } from "../mock/MockReceivables.sol";
import { RevenueToken } from "../mock/RevenueToken.sol";
import { RevenueToken4626 } from "../mock/RevenueToken4626.sol";

import { LineLib } from "../utils/LineLib.sol";
import { CreditLib } from "../utils/CreditLib.sol";
import { CreditListLib } from "../utils/CreditListLib.sol";


contract LineLibTest is Test {
    using CreditListLib for bytes32[];
    bytes32[] private ids;

    address lender = address(0xf1c0);
    address line = address(0xdebf);
    RevenueToken token = new RevenueToken();
    address tkn = address(token);
    MockReceivables receivables = new MockReceivables();

    // getBalance

    function test_get_balance_ETH() public {
      uint bal = address(this).balance;
      uint getBal = LineLib.getBalance(Denominations.ETH);
      
      assertEq(bal, getBal);
      
      deal(address(this), 1 ether);

      uint bal2 = address(this).balance;
      uint getBal2 = LineLib.getBalance(Denominations.ETH);

      assertEq(bal2, getBal2);
      assertEq(bal2, 1 ether);
    }

    function test_get_balance_is_0_if_null() public {
      assertEq(0, LineLib.getBalance(address(0)));
    }

    function test_get_balance_token() public {
      uint bal = token.balanceOf(address(this));
      uint getBal = LineLib.getBalance(tkn);
      
      assertEq(bal, getBal);
      
      // deal(address(this), address(token), 1 ether);
      token.mint(address(this), 1 ether);

      uint bal2 = token.balanceOf(address(this));
      uint getBal2 = LineLib.getBalance(tkn);

      assertEq(bal2, getBal2);
      assertEq(bal2, 1 ether);
    }

    function test_get_balance_4626() public {
      // 4626 conforms to ERC20 so just getBalance
      RevenueToken4626 token4626 = new RevenueToken4626(tkn);

      // make sure getBalance returns 4626 tokens not total amount of underlying tokens
      uint bal = token.balanceOf(address(this));
      uint getBal = LineLib.getBalance(address(token4626));
      
      assertEq(bal, getBal);
      
      // deal(address(this), address(token4626), 1 ether);
      token4626.mint(address(this), 1 ether);

      uint bal2 = token4626.balanceOf(address(this));
      uint getBal2 = LineLib.getBalance(address(token4626));

      assertEq(bal2, getBal2);
      assertEq(bal2, 1 ether);
    }

    function test_cant_get_balance_of_non_ERC20_token() public {
      vm.expectRevert();
      uint getBal = LineLib.getBalance(address(this));
    }

    // receiveTokenOrETH

    function test_must_have_msgValue_to_receive_ETH() public {
      vm.expectRevert(LineLib.TransferFailed.selector);
      // nothing sent in this tx
      receivables.accept(Denominations.ETH, address(this), 1 ether);
    }

    function test_sending_eth_fails_if_sending_to_contract_without_receivable_function() external {
      MockStatefulReceivables statefulReceivables = new MockStatefulReceivables();
      statefulReceivables.setReceiveableState(false);
  
      vm.deal(address(receivables), 1 ether); 
      
      vm.expectRevert(LineLib.SendingEthFailed.selector);
      receivables.send(Denominations.ETH, address(statefulReceivables), 0.5 ether);

    }


    function test_can_receive_ETH_via_msgValue() public {
      deal(address(this), 1 ether);
      receivables.accept{value: 1 ether}(Denominations.ETH, address(this), 1 ether);
    }



    function test_can_transfer_tokens_from_sender_to_recieve()  public {
      token.mint(address(this), 1 ether);
      token.approve(address(receivables), 1 ether);
      receivables.accept(tkn, address(this), 1 ether);
    }


    // sendOutTokenOrETH

    function test_send_out_ETH() public {
      uint thisBal = LineLib.getBalance(Denominations.ETH);
      uint thatBal = receivables.balance(Denominations.ETH);

      deal(address(receivables), 1 ether);
      receivables.send(Denominations.ETH, address(this), 1 ether);
      // this +1 from send()
      assertEq(thisBal + 1 ether, LineLib.getBalance(Denominations.ETH));
      // that no change. minted then transfered
      assertEq(thatBal, receivables.balance(Denominations.ETH));
    }

    function test_send_out_fails_if_null() public {
      vm.expectRevert(LineLib.TransferFailed.selector);
      LineLib.sendOutTokenOrETH(address(0), address(receivables), 1 ether);
    }

    function test_send_out_token() public {
      uint thisBal = LineLib.getBalance(tkn);
      uint thatBal = receivables.balance(tkn);
      
      token.mint(address(receivables), 1 ether);
      receivables.send(tkn, address(this), 1 ether);
      // +1 from send()
      assertEq(thisBal + 1 ether, LineLib.getBalance(tkn));
      // no change. minted then transfered
      assertEq(thatBal,  receivables.balance(tkn));
    }

    // Test refunding overpaid


    function test_send_out_4626() public {
      RevenueToken4626 token4626 = new RevenueToken4626(tkn);

      uint thisBal = LineLib.getBalance(address(token4626));
      uint thatBal = receivables.balance(address(token4626));

      
      token4626.mint(address(receivables), 1 ether);
      receivables.send(address(token4626), address(this), 1 ether);
      // +1 from send()
      assertEq(thisBal + 1 ether, LineLib.getBalance(address(token4626)));
      // no change. minted then transfered
      assertEq(thatBal,  receivables.balance(address(token4626)));
    }


    // computeId

    function test_computes_the_same_position_id() public view {
        bytes32 id = CreditLib.computeId(line, lender, tkn);
        bytes32 id2 = CreditLib.computeId(line, lender, tkn);
        assert(id == id2);
    }

    function test_computes_a_different_position_id() public view {
        bytes32 id = CreditLib.computeId(line, lender, tkn);
        bytes32 id2 = CreditLib.computeId(line, address(this), tkn);
        assert(id != id2);
        bytes32 idSameInputsDifferentOrder = CreditLib.computeId(lender, line, tkn);
        assert(idSameInputsDifferentOrder != id);
    }

    function test_can_remove_position() public {
        bytes32 id = CreditLib.computeId(line, lender, tkn);
        bytes32 id2 = CreditLib.computeId(line, address(this), tkn);
        ids.push(id);
        ids.push(id2);
        
        assert(ids.length == 2);
        ids.removePosition(id2);
        assert(ids.length == 2); // not deleted, only null

        assert(ids[0] == id);
        assert(ids[1] == bytes32(0)); // ensure deleted
    }


    function test_cannot_remove_non_existent_position() public {
        bytes32 id = CreditLib.computeId(line, lender, tkn);
        ids.push(id);
        assert(ids.length == 1);
        ids.removePosition(bytes32(0));
        assert(ids.length == 1);
        assertEq(ids[0], id);
    }


    function test_can_properly_step_queue(uint256 length) public {
        uint l = 10;
        ids = new bytes32[](l);
        // ensure array is within reasonable bounds
        vm.assume(length != 0 && length < ids.length);
        if(length == 1) {
            ids[0] = bytes32(0);
            ids.stepQ();
            assertEq(ids[0], ids[0]);
            return;
        }

        if(length == 2) {
            ids[0] = bytes32(0);
            ids[1] = bytes32(uint(1));

            ids.stepQ();
            assertEq(ids[0], bytes32(uint(1)));
            assertEq(ids[1], bytes32(0));
            return;
        }

        for(uint256 i = 0; i < length; i++) {
          ids[i] == bytes32(i);
        }
        ids.stepQ();
        
        assertEq(ids.length, l);
        
        for(uint256 i = 0; i < l; i++) {
          if(i == 0) assertEq(ids[i], ids[l - 1]); // first -> last
          else assertEq(ids[i], ids[i - 1]);      // all others move one index down
        }
    }

    

    receive() external payable {} // can receive ETH from tests
}
