pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import {InterestRateCredit} from "./InterestRateCredit.sol";

contract InterestRateCreditTest is Test {
    InterestRateCredit i;

    function setUp() public {
        i = new InterestRateCredit();
        vm.warp(0);
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
        i.setRate(bytes32(""), uint128(1), uint128(1));
        skip(3812);
        uint256 accrued = i.accrueInterest(bytes32(0), 3, 3);
        assertEq(accrued, 0);
    }

    function test_accrue_interest_drawn_with_no_facility_rate(
        uint128 drawnRate,
        uint256 drawnBalance
    ) public {
        vm.assume(drawnRate > 0 && drawnRate <= 1e4);
        vm.assume(
            drawnBalance >= 1e4 &&
                drawnBalance < 99999999999999999999999999999999999999
        );
        bytes32 id = bytes32("");
        i.setRate(id, drawnRate, uint128(0));
        skip(365.25 days);
        uint256 accrued = i.accrueInterest(id, drawnBalance, drawnBalance);
        assertEq(accrued, (drawnRate * drawnBalance) / 1e4);
    }

    function test_accrue_interest_drawn_half_drawn(uint256 balance) public {
        vm.assume(
            balance >= 2e4 && balance < 99999999999999999999999999999999999999
        );

        bytes32 id = bytes32("");
        uint128 drawnRate = 603;
        uint128 facilityRate = 118;
        uint256 drawnBalance = balance / 2;
        uint256 facilityBalance = balance;

        i.setRate(id, drawnRate, facilityRate);
        skip(365.25 days);
        uint256 accrued = i.accrueInterest(id, drawnBalance, facilityBalance);

        assertEq(
            accrued,
            (((drawnRate * drawnBalance) / 1e4) +
                ((facilityRate * (facilityBalance - drawnBalance)) / 1e4))
        );
    }

    function test_can_accrue_interest_none_drawn() public {
        i.setRate(bytes32(""), uint128(0), uint128(0));
        uint256 accrued = i.accrueInterest(bytes32(0), 0, 1);
        assertEq(accrued, 0); // TODO: figure out how to fast forward blocks in hevm to test real amounts
    }

    function test_lastAccrued_update() public {
        uint256 prevBlocktime = block.timestamp;
        uint256 timeToSkip = 98381;
        bytes32 id = bytes32("");
        i.setRate(id, uint128(0), uint128(0));
        skip(timeToSkip);
        i.accrueInterest(bytes32(0), 0, 1);
        (, , uint256 lastAccrued) = i.rates(id);
        assertEq(lastAccrued, prevBlocktime + timeToSkip);
    }
}
