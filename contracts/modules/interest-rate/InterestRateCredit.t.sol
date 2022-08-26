pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import {InterestRateCredit} from "./InterestRateCredit.sol";

contract InterestRateCreditTest is Test {
    InterestRateCredit i;

    function setUp() public {
        i = new InterestRateCredit();
    }

    function test_can_add_different_rates() public {
        i.setRate(bytes32(""), uint128(0), uint128(0));
        (uint128 d, uint128 f, uint256 l) = i.rates(bytes32(""));
        assertEq(d, 0);
        assertEq(f, 0);
        assertEq(l, block.timestamp);
        i.setRate(bytes32("1"), uint128(1), uint128(1));
        (d, f, l) = i.rates(bytes32("1"));
        assertEq(d, 1);
        assertEq(f, 1);
        assertEq(l, block.timestamp);
    }

    function test_can_accrue_interest_all_drawn() public {
        i.setRate(bytes32(""), uint128(0), uint128(0));
        uint256 accrued = i.accrueInterest(bytes32(0), 1, 1);
        assertEq(accrued, 0); // TODO: figure out how to fast forward blocks in hevm to test real amounts
    }

    function test_can_accrue_interest_half_drawn() public {
        i.setRate(bytes32(""), uint128(0), uint128(0));
        uint256 accrued = i.accrueInterest(bytes32(0), 1, 2);
        assertEq(accrued, 0); // TODO: figure out how to fast forward blocks in hevm to test real amounts
    }

    function test_can_accrue_interest_none_drawn() public {
        i.setRate(bytes32(""), uint128(0), uint128(0));
        uint256 accrued = i.accrueInterest(bytes32(0), 0, 1);
        assertEq(accrued, 0); // TODO: figure out how to fast forward blocks in hevm to test real amounts
    }

    function test_lastAccrued_update() public {
        uint prevBlocktime = block.timestamp;
        uint timeToSkip = 98381;
        bytes32 id = bytes32("");
        i.setRate(id, uint128(0), uint128(0));
        skip(timeToSkip);
        i.accrueInterest(bytes32(0), 0, 1);
        (, , uint256 lastAccrued) = i.rates(id);
        assertEq(lastAccrued, prevBlocktime + timeToSkip);
    }
}
