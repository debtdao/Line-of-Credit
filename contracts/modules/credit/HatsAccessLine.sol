
pragma solidity 0.8.16;
import {LineLib} from "../../utils/LineLib.sol";
import {SecuredLine} from "./SecuredLine.sol";

contract HatsAccessLine is SecuredLine {
    /// @notice the Hats protocol hat that manages access to this line of credit
    address immutable hat;
    constructor(address _hat) {
        hat = _hat
    }

    function _canBorrow(address caller) internal virtual override returns (bool) {
        if (super._canBorrow() /** || hat.isWearer(caller) (+ max limit if possible) */) {
            return true;
        }
    }

}