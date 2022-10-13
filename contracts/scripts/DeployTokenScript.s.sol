import {RevToken} from "../../contracts/mock/RevToken.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract DeployTokenScript is Script {
    
    RevToken mooCoin;
    RevToken kiibaCoin;
    RevToken seeroCoin;


    address mintee = 0xf44B95991CaDD73ed769454A03b3820997f00873;
    uint mintAmount = 10000000000 ether;
    
   

    function run() external {
        
        uint256 deployerPrivateKey= vm.envUint("MO_KEY");
        vm.startBroadcast(deployerPrivateKey);

        mooCoin = new RevToken("MooCoin", "MOO");
        seeroCoin = new RevToken("SeeroCoin", "SEERO");
        kiibaCoin = new RevToken("KiibaCoin", "KIIBA");


        mooCoin.mint(mintee, mintAmount);
        seeroCoin.mint(mintee, mintAmount);
        kiibaCoin.mint(mintee, mintAmount);


        vm.stopBroadcast();
    }
}