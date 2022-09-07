pragma solidity 0.8.9;

import {IEscrow} from "../../interfaces/IEscrow.sol";
import {LineLib} from "../../utils/LineLib.sol";
import {IEscrowedLine} from "../../interfaces/IEscrowedLine.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";

abstract contract EscrowedLine is IEscrowedLine, ILineOfCredit {
    // contract holding all collateral for borrower
    IEscrow public immutable escrow;

    constructor(address _escrow) {
        escrow = IEscrow(_escrow);
    }

    function _init() internal virtual returns (LineLib.STATUS) {
        if (escrow.line() != address(this)) {
            return LineLib.STATUS.UNINITIALIZED;
        }
        return LineLib.STATUS.ACTIVE;
    }

    /**
     * @dev see BaseLine._healthcheck
     */
    function _healthcheck() internal virtual returns (LineLib.STATUS) {
        if (escrow.isLiquidatable()) {
            return LineLib.STATUS.LIQUIDATABLE;
        }

        return LineLib.STATUS.ACTIVE;
    }

    /**
     * @notice sends escrowed tokens to liquidation.
     * (@dev priviliegad function. Do checks before calling.
     * @param positionId - position being repaid in liquidation
     * @param amount - amount of tokens to take from escrow and liquidate
     * @param targetToken - the token to take from escrow
     * @param to - the liquidator to send tokens to. could be OTC address or smart contract
     * @return amount - the total amount of `targetToken` sold to repay credit
     *
     */
    function _liquidate(bytes32 positionId, uint256 amount, address targetToken, address to)
        internal
        virtual
        returns (uint256)
    {
        IEscrow escrow_ = escrow; // gas savings
        require(escrow_.liquidate(amount, targetToken, to));

        emit Liquidate(positionId, amount, targetToken, address(escrow_));

        return amount;
    }

    /**
     * @notice require all collateral sold off before declaring insolvent
     * (@dev priviliegad internal function.
     * @return if line is insolvent or not
     */
    function _canDeclareInsolvent() internal virtual returns (bool) {
        if (escrow.getCollateralValue() != 0) {
            revert NotInsolvent(address(escrow));
        }
        return true;
    }

    function _rollover(address newLine) internal virtual returns (bool) {
        require(escrow.updateLine(newLine));
        return true;
    }
}
