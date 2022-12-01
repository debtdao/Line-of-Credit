pragma solidity 0.8.9;

import {CreditLib} from "../utils/CreditLib.sol";
import {CreditListLib} from "../utils/CreditListLib.sol";
import {EscrowLib} from "../utils/EscrowLib.sol";
import {LineFactoryLib} from "../utils/LineFactoryLib.sol";
import {LineLib} from "../utils/LineLib.sol";
import {SpigotedLineLib} from "../utils/SpigotedLineLib.sol";
import {SpigotLib} from "../utils/SpigotLib.sol";

contract MockRegistry {
    address public creditLib;
    address public creditListLib;
    address public escrowLib;
    address public lineFactoryLib;
    address public lineLib;
    address public spigotedLineLib;
    address public spigotLib;

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
