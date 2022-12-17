pragma solidity 0.8.9;

import {CreditLib} from "./CreditLib.sol";
import {CreditListLib} from "./CreditListLib.sol";
import {EscrowLib} from "./EscrowLib.sol";
import {LineFactoryLib} from "./LineFactoryLib.sol";
import {LineLib} from "./LineLib.sol";
import {SpigotedLineLib} from "./SpigotedLineLib.sol";
import {SpigotLib} from "./SpigotLib.sol";

contract LibRegistry {
    address public immutable creditLib;
    address public immutable creditListLib;
    address public immutable escrowLib;
    address public immutable lineFactoryLib;
    address public immutable lineLib;
    address public immutable spigotedLineLib;
    address public immutable spigotLib;

    constructor() {
        creditLib = address(CreditLib);
        creditListLib = address(CreditListLib);
        escrowLib = address(EscrowLib);
        lineFactoryLib = address(LineFactoryLib);
        lineLib = address(LineLib);
        spigotedLineLib = address(SpigotedLineLib);
        spigotLib = address(SpigotLib);
    }
}
