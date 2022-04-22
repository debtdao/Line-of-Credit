pragma solidity 0.8.9;

import { DSTest } from "../../lib/ds-test/src/test.sol";
import { LoanLib } from "./LoanLib.sol";

contract LoanLibTest is DSTest {

    address lender = address(0);
    address loan = address(1);
    address token = address(2);

    function test_computes_the_same_position_id() public {
        bytes32 positionId = LoanLib.computePositionId(loan, lender, token);
        bytes32 positionId2 = LoanLib.computePositionId(loan, lender, token);
        assert(positionId == positionId2);
    }

    function test_computes_a_different_position_id() public {
        bytes32 positionId = LoanLib.computePositionId(loan, lender, token);
        bytes32 positionId2 = LoanLib.computePositionId(loan, address(this), token);
        assert(positionId != positionId2);
        bytes32 positionIdSameInputsDifferentOrder = LoanLib.computePositionId(lender, loan, token);
        assert(positionIdSameInputsDifferentOrder != positionId);
    }

    function test_can_remove_position() public {
        bytes32 positionId = LoanLib.computePositionId(loan, lender, token);
        bytes32 positionId2 = LoanLib.computePositionId(loan, address(this), token);
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = positionId;
        ids[1] = positionId2;
        assert(ids.length == 2);
        bytes32[] memory newIds = LoanLib.removePosition(ids, positionId2);
        assert(newIds.length == 1);
        assert(newIds[0] == positionId);
    }

    function testFail_cannot_remove_non_existent_position() public {
        bytes32 positionId = LoanLib.computePositionId(loan, lender, token);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = positionId;
        assert(ids.length == 1);
        LoanLib.removePosition(ids, bytes32(0));
    }

}
