pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LineLib} from "../../utils/LineLib.sol";
import {EscrowedLine} from "./EscrowedLine.sol";
import {SpigotedLine} from "./SpigotedLine.sol";
import {SpigotedLineLib} from "../../utils/SpigotedLineLib.sol";
import {LineOfCredit} from "./LineOfCredit.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";
import {ISecuredLine} from "../../interfaces/ISecuredLine.sol";

contract SecuredLine is SpigotedLine, EscrowedLine, ISecuredLine {
    constructor(
        address oracle_,
        address arbiter_,
        address borrower_,
        address payable swapTarget_,
        address spigot_,
        address escrow_,
        uint256 ttl_,
        uint8 defaultSplit_
    )
        SpigotedLine(oracle_, arbiter_, borrower_, spigot_, swapTarget_, ttl_, defaultSplit_)
        EscrowedLine(escrow_)
    {}

    function _init() internal virtual override (SpigotedLine, EscrowedLine) returns (LineLib.STATUS) {
        LineLib.STATUS s = LineLib.STATUS.ACTIVE;

        if (SpigotedLine._init() != s || EscrowedLine._init() != s) {
            return LineLib.STATUS.UNINITIALIZED;
        }

        return s;
    }

    function rollover(address newLine) external override onlyBorrower returns (bool) {
        // require all debt successfully paid already
        if (status != LineLib.STATUS.REPAID) {
            revert DebtOwed();
        }
        // require new line isn't activated yet
        if (ILineOfCredit(newLine).status() != LineLib.STATUS.UNINITIALIZED) {
            revert BadNewLine();
        }
        // we dont check borrower is same on both lines because borrower might want new address managing new line
        EscrowedLine._rollover(newLine);
        SpigotedLineLib.rollover(address(spigot), newLine);

        // ensure that line we are sending can accept them. There is no recovery option.
        if (ILineOfCredit(newLine).init() != LineLib.STATUS.ACTIVE) {
            revert BadRollover();
        }

        return true;
    }

    // Liquidation
    /**
     * @notice - Forcefully take collateral from borrower and repay debt for lender
     * @dev - only called by neutral arbiter party/contract
     * @dev - `status` must be LIQUIDATABLE
     * @dev - callable by `arbiter`
     * @param amount - amount of `targetToken` expected to be sold off in  _liquidate
     * @param targetToken - token in escrow that will be sold of to repay position
     */

    function liquidate(uint256 amount, address targetToken) external whileBorrowing returns (uint256) {
        if (msg.sender != arbiter) {
            revert CallerAccessDenied();
        }
        if (_updateStatus(_healthcheck()) != LineLib.STATUS.LIQUIDATABLE) {
            revert NotLiquidatable();
        }

        // send tokens to arbiter for OTC sales
        return _liquidate(ids[0], amount, targetToken, msg.sender);
    }

    /**
     * @notice checks internal accounting logic for status and if ok, runs modules checks
     */
    function _healthcheck() internal override (EscrowedLine, LineOfCredit) returns (LineLib.STATUS) {
        LineLib.STATUS s = LineOfCredit._healthcheck();
        if (s != LineLib.STATUS.ACTIVE) {
            return s;
        }

        return EscrowedLine._healthcheck();
    }

    /// @notice all insolvency conditions must pass for call to succeed
    function _canDeclareInsolvent() internal virtual override (EscrowedLine, SpigotedLine) returns (bool) {
        return (EscrowedLine._canDeclareInsolvent() && SpigotedLine._canDeclareInsolvent());
    }
}
