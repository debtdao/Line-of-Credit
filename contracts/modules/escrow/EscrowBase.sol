pragma solidity 0.8.9;

import {EscrowState} from "../../utils/EscrowLib.sol";

contract EscrowBase {
    EscrowState internal escrow;

    constructor(
        uint256 _minimumCollateralRatio,
        address _oracle,
        address _line,
        address _borrower
    ) {
        escrow.minimumCollateralRatio = _minimumCollateralRatio;
        escrow.oracle = _oracle;
        escrow.line = _line;
        escrow.borrower = _borrower;
    }
}
