pragma solidity ^0.8.9;

import {IInterestRateCredit} from "../../interfaces/IInterestRateCredit.sol";

contract InterestRateCredit is IInterestRateCredit {
    uint256 constant ONE_YEAR = 365.25 days; // one year in sec to use in calculations for rates
    uint256 constant BASE_DENOMINATOR = 10000; // div 100 for %, div 100 for bps in numerator
    uint256 constant INTEREST_DENOMINATOR = ONE_YEAR * BASE_DENOMINATOR;

    address immutable lineContract;
    mapping(bytes32 => Rate) public rates; // id -> lending rates

    /**
     * @notice Interest rate / acrrued interest calculation contract for Line of Credit contracts
     */
    constructor() {
        lineContract = msg.sender;
    }

    ///////////  MODIFIERS  ///////////

    modifier onlyLineContract() {
        require(
            msg.sender == lineContract,
            "InterestRateCred: only line contract."
        );
        _;
    }

    ///////////  FUNCTIONS  ///////////

    /**
     * @dev accrueInterest function for Line of Credit contracts
     * @dev    - callable by `line`
     * @param drawnBalance (the balance of funds that a Borrower has drawn down on the credit line)
     * @param facilityBalance (the remaining balance of funds that a Borrower can still drawn down on a credit line (aka headroom))
     * @return repayBalance (the amount of interest to be repaid for this interest period)
     *
     */
    function accrueInterest(
        bytes32 id,
        uint256 drawnBalance,
        uint256 facilityBalance
    ) external override onlyLineContract returns (uint256) {
        return _accrueInterest(id, drawnBalance, facilityBalance);
    }

    function _accrueInterest(
        bytes32 id,
        uint256 drawnBalance,
        uint256 facilityBalance
    ) internal returns (uint256) {
        Rate memory rate = rates[id];
        uint256 timespan = block.timestamp - rate.lastAccrued;
        rates[id].lastAccrued = block.timestamp;
        rates[id] = rate;

        // r = APR in BPS, x = # tokens, t = time
        // interest = (r * x * t) / 1yr / 100
        // facility = deposited - drawn (aka undrawn balance)
        return (((rate.dRate * drawnBalance * timespan) /
            INTEREST_DENOMINATOR) +
            ((rate.fRate * (facilityBalance - drawnBalance) * timespan) /
                INTEREST_DENOMINATOR));
    }

    /**
     * @notice update interest rates for a credit line
     * @dev - Line contract responsible for calling accrueInterest() before updateInterest() if necessary
     * @dev    - callable by `line`
     */
    function setRate(
        bytes32 id,
        uint128 dRate,
        uint128 fRate
    ) external onlyLineContract returns (bool) {
        rates[id] = Rate({
            dRate: dRate,
            fRate: fRate,
            lastAccrued: block.timestamp
        });

        return true;
    }
}
