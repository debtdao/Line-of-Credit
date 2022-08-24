pragma solidity 0.8.9;

import {EscrowState, EscrowLib} from "../../utils/EscrowLib.sol";
import {EscrowBase} from "../escrow/EscrowBase.sol";
import {LineLib} from "../../utils/LineLib.sol";
import {IEscrowedLine} from "../../interfaces/IEscrowedLine.sol";
import {ILineOfCredit} from "../../interfaces/ILineOfCredit.sol";

abstract contract EscrowedLine is EscrowBase, IEscrowedLine, ILineOfCredit {
    using EscrowLib for EscrowState;

    function _init() internal virtual returns (LineLib.STATUS) {
        if (escrow.getLine() != address(this))
            return LineLib.STATUS.UNINITIALIZED;
        return LineLib.STATUS.ACTIVE;
    }

    /** @dev see BaseLine._healthcheck */
    function _healthcheck() internal virtual returns (LineLib.STATUS) {
        if (escrow.isLiquidatable()) {
            return LineLib.STATUS.LIQUIDATABLE;
        }

        return LineLib.STATUS.ACTIVE;
    }

    /**
     * @notice sends escrowed tokens to liquidation.
     *(@dev priviliegad function. Do checks before calling.
     * @param positionId - position being repaid in liquidation
     * @param amount - amount of tokens to take from escrow and liquidate
     * @param targetToken - the token to take from escrow
     * @param to - the liquidator to send tokens to. could be OTC address or smart contract
     * @return amount - the total amount of `targetToken` sold to repay credit
     *
     */
    function _liquidate(
        bytes32 positionId,
        uint256 amount,
        address targetToken,
        address to
    ) internal virtual returns (uint256) {
        require(escrow.liquidate(amount, targetToken, to));

        emit Liquidate(positionId, amount, targetToken);

        return amount;
    }

    /**
     * @notice require all collateral sold off before declaring insolvent
     *(@dev priviliegad internal function.
     * @return if line is insolvent or not
     */
    function _canDeclareInsolvent() internal virtual returns (bool) {
        if (escrow.getCollateralValue() != 0) {
            revert NotInsolvent(address(EscrowLib));
        }
        return true;
    }

    function _rollover(address newLine) internal virtual returns (bool) {
        require(escrow.updateLine(newLine));
        return true;
    }
}
