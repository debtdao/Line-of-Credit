import {RevToken} from "../../contracts/mock/RevToken.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";

contract ApprovalScript is Script {
    RevToken mooCoin;
    RevToken kiibaCoin;
    RevToken seeroCoin;
    SecuredLine line;
    Escrow escrow;

    address kiba = address(0xDe8f0F6769284e41Bf0f82d0545141c15A3E4aD1);
    address sero = address(0x1A6784925814a13334190Fd249ae0333B90b6443);
    address mo = address(0xf44B95991CaDD73ed769454A03b3820997f00873);

    uint constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

     function run() public {
        // uint256 deployerPrivateKey= vm.envUint("MO_KEY");
        // vm.startBroadcast(deployerPrivateKey);

        uint256 deployerPrivateKey= vm.envUint("CRAIG_KEY");
        vm.startBroadcast(deployerPrivateKey);

        line = SecuredLine(payable(0xE88790286AfD3DE0Ae0144706476287e2Cd08874));
        address line_add = address(line);
        address escrow_add = address(line.escrow());
 

        mooCoin = RevToken(address(0xe62e4B079D40CF643D3b4963e4B675eC101928df));
        kiibaCoin = RevToken(address(0x3D4AA21e8915F3b5409BDb20f76457FCdAF8f757));
        seeroCoin = RevToken(address(0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6));

        // mooCoin.approve(address(escrow_add), MAX_INT);
        // kiibaCoin.approve(address(escrow_add), MAX_INT);
        // seeroCoin.approve(address(escrow_add), MAX_INT);

        mooCoin.approve(address(line_add), MAX_INT);
        kiibaCoin.approve(address(line_add), MAX_INT);
        seeroCoin.approve(address(line_add), MAX_INT);

    }
}
