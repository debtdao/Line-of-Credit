pragma solidity 0.8.9;

import { DSTest } from "../../lib/ds-test/src/test.sol";
import { LoanLib } from "./LoanLib.sol";

contract LoanLibTest is DSTest {

    address lender = address(0);
    address loan = address(1);
    address token = address(2);

    function test_computes_the_same_position_id() public {
        bytes32 id = LoanLib.computePositionId(loan, lender, token);
        bytes32 id2 = LoanLib.computePositionId(loan, lender, token);
        assert(id == id2);
    }

    function test_computes_a_different_position_id() public {
        bytes32 id = LoanLib.computePositionId(loan, lender, token);
        bytes32 id2 = LoanLib.computePositionId(loan, address(this), token);
        assert(id != id2);
        bytes32 idSameInputsDifferentOrder = LoanLib.computePositionId(lender, loan, token);
        assert(idSameInputsDifferentOrder != id);
    }

    function test_can_remove_position() public {
        bytes32 id = LoanLib.computePositionId(loan, lender, token);
        bytes32 id2 = LoanLib.computePositionId(loan, address(this), token);
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id;
        ids[1] = id2;
        assert(ids.length == 2);
        bytes32[] memory newIds = LoanLib.removePosition(ids, id2);
        assert(newIds.length == 1);
        assert(newIds[0] == id);
    }

    function testFail_cannot_remove_non_existent_position() public {
        bytes32 id = LoanLib.computePositionId(loan, lender, token);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;
        assert(ids.length == 1);
        LoanLib.removePosition(ids, bytes32(0));
    }


    function test_can_properly_step_queue(uint256 length) public {
        if(length == 0 || length > 200) { return; } // ensure array is within reasonable bounds

        bytes32[] memory ids = new bytes32[](length);
        if(length == 1) {
            ids[0] = bytes32(0);
            bytes32[] memory newIds = LoanLib.stepQ(ids);
            assertEq(newIds[0], ids[0]);
            return;
        }

        if(length == 2) {
            ids[0] = bytes32(0);
            ids[1] = bytes32(uint(1));

            bytes32[] memory newIds = LoanLib.stepQ(ids);
            assertEq(newIds[0], ids[1]);
            assertEq(newIds[1], ids[0]);
            return;
        }

        for(uint256 i = 0; i < length; i++) {
          ids[i] == bytes32(i);
        }
        bytes32[] memory newIds = LoanLib.stepQ(ids);
        
        assertEq(newIds.length, length);
        
        for(uint256 i = 0; i < length; i++) {
          if(i == 0) assertEq(ids[i], newIds[length - 1]); // first -> last
          else assertEq(ids[i], newIds[i - 1]);    // all others move one index down
        }
    }

    function test_calculates_right_price_w_decimals(int256 price, uint256 amount) public {
        // no negative values, base 0 
        if(price < 0) return;
        // TODO constrain params so price * amount doesn't overflow

        uint realPrice = uint256(price);
        uint8 decimals = 18;
        uint8 decimals2 = 1;
        

        uint val = LoanLib.calculateValue(price, amount, decimals);
        assertEq(val,  realPrice * amount * ( 1 * 10 ** decimals));

        uint val2 = LoanLib.calculateValue(price, amount, decimals2);
        assertEq(val2,  realPrice * amount * ( 1 * 10 ** decimals2));
    }
}
