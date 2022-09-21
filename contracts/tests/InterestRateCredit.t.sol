pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import {InterestRateCredit} from "../modules/interest-rate/InterestRateCredit.sol";

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

    function test_can_accrue_interest_all_drawn(
        uint128 drawnRate,
        uint64 drawnBalance
    ) public {
        vm.assume(drawnRate > 0 && drawnRate <= 1e4);
        vm.assume(drawnBalance >= 1e4);
        bytes32 id = bytes32("");
        i.setRate(id, drawnRate, uint128(3));
        skip(365.25 days);
        uint256 accrued = i.accrueInterest(id, drawnBalance, drawnBalance);
        assertEq(accrued, (drawnRate * drawnBalance) / 1e4);
    }

    function test_accrue_interest_drawn_half_drawn(uint200 balance) public {
        vm.assume(balance >= 2e4);

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

    function test_can_accrue_interest_none_drawn(uint200 balance) public {
        bytes32 id = bytes32("");
        uint128 facilityRate = 71;
        uint256 facilityBalance = balance;
        i.setRate(id, uint128(3), uint128(facilityRate));
        skip(365.25 days);
        uint256 accrued = i.accrueInterest(id, 0, facilityBalance);
        assertEq(accrued, (facilityRate * facilityBalance) / 1e4);
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

    function test_past_date() public {
        bytes32 id = bytes32("");
        i.setRate(id, uint128(3), uint128(51));
        skip(630 days);
        uint256 accrued = i.accrueInterest(id, 0, 393924332895329);
        console2.log("accU:", accrued);
        assertEq(accrued, 3465239922225);
    }
}
