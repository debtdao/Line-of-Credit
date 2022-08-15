pragma solidity 0.8.9;


import "forge-std/Test.sol";

import { LoanLib } from "./LoanLib.sol";
import { CreditLib } from "./CreditLib.sol";
import { CreditListLib } from "./CreditListLib.sol";


contract LoanLibTest is Test {
    using CreditListLib for bytes32[];
    bytes32[] private ids;

    address lender = address(0);
    address loan = address(1);
    address token = address(2);

    function test_computes_the_same_position_id() public view {
        bytes32 id = CreditLib.computeId(loan, lender, token);
        bytes32 id2 = CreditLib.computeId(loan, lender, token);
        assert(id == id2);
    }

    function test_computes_a_different_position_id() public view {
        bytes32 id = CreditLib.computeId(loan, lender, token);
        bytes32 id2 = CreditLib.computeId(loan, address(this), token);
        assert(id != id2);
        bytes32 idSameInputsDifferentOrder = CreditLib.computeId(lender, loan, token);
        assert(idSameInputsDifferentOrder != id);
    }

    function test_can_remove_position() public {
        bytes32 id = CreditLib.computeId(loan, lender, token);
        bytes32 id2 = CreditLib.computeId(loan, address(this), token);
        ids.push(id);
        ids.push(id2);
        
        assert(ids.length == 2);
        ids.removePosition(id2);
        assert(ids.length == 2); // not deleted, only null

        assert(ids[0] == id);
        assert(ids[1] == bytes32(0)); // ensure deleted
    }


    function test_cannot_remove_non_existent_position() public {
        bytes32 id = CreditLib.computeId(loan, lender, token);
        ids.push(id);
        assert(ids.length == 1);
        ids.removePosition(bytes32(0));
        assert(ids.length == 1);
        assertEq(ids[0], id);
    }


    function test_can_properly_step_queue(uint256 length) public {
        uint l = 10;
        ids = new bytes32[](l);
        if(length == 0 || length > ids.length) { return; } // ensure array is within reasonable bounds
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

    function test_calculates_right_price_w_decimals(int256 price, uint256 amount) public {
        // no negative values, base 0 
        if(price < 0) return;
        // TODO constrain params so price * amount doesn't overflow

        uint realPrice = uint256(price);
        uint8 decimals = 18;
        uint8 decimals2 = 1;
        

        uint val = CreditLib.calculateValue(price, amount, decimals);
        assertEq(val,  realPrice * amount * ( 1 * 10 ** decimals));

        uint val2 = CreditLib.calculateValue(price, amount, decimals2);
        assertEq(val2,  realPrice * amount * ( 1 * 10 ** decimals2));
    }
}
