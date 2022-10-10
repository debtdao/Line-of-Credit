import {Script} from "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";


contract LineScript is Script {

    SecuredLine line;
    Escrow escrow;
    uint256 amount = 1000000000 ether;

    function run() public {
        uint256 deployerPrivateKey= vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        line = SecuredLine(payable(0xE88790286AfD3DE0Ae0144706476287e2Cd08874));
        address escrow_add = address(line.escrow());
    
        escrow = Escrow(payable(escrow_add));
        // escrow.enableCollateral(address(0x3D4AA21e8915F3b5409BDb20f76457FCdAF8f757));
        // escrow.addCollateral(amount, address(0x3D4AA21e8915F3b5409BDb20f76457FCdAF8f757));
        line.addCredit(2000, 1000, 2000000000 ether, address(0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6), address(0x1A6784925814a13334190Fd249ae0333B90b6443));

    }
}
