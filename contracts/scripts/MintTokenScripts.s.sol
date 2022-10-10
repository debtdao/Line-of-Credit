import {RevToken} from "../../contracts/mock/RevToken.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract MintTokenScript is Script {
    
    RevToken mooCoin;
    RevToken kiibaCoin;
    RevToken seeroCoin;


    address mintee = 0xf44B95991CaDD73ed769454A03b3820997f00873;
    uint mintAmount = 10000000000 ether;
    
    function run() public {
        uint256 deployerPrivateKey= vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        mooCoin = RevToken(address(0xe62e4B079D40CF643D3b4963e4B675eC101928df));
        // mooCoin.mint(mintee, mintAmount);

        kiibaCoin = RevToken(address(0x3D4AA21e8915F3b5409BDb20f76457FCdAF8f757));
        kiibaCoin.mint(mintee, mintAmount);

        seeroCoin = RevToken(address(0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6));
        seeroCoin.mint(mintee, mintAmount);
    }
}