import {RevToken} from "../../contracts/mock/RevToken.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract TransferTokenScript is Script {
    RevToken mooCoin;
    RevToken kiibaCoin;
    RevToken seeroCoin;

    address kiba = address(0xDe8f0F6769284e41Bf0f82d0545141c15A3E4aD1);
    address sero = address(0x1A6784925814a13334190Fd249ae0333B90b6443);
    address mo = address(0xf44B95991CaDD73ed769454A03b3820997f00873);
    address craig = address(0x0980510F95F4fAB5629a497F9FeA58a1f44FC121);
    uint256 amount = 2000000000 ether;

    function run() public {
        uint256 deployerPrivateKey= vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // uint256 deployerPrivateKey= vm.envUint("CRAIG_KEY");
        // vm.startBroadcast(deployerPrivateKey);

        mooCoin = RevToken(address(0xe62e4B079D40CF643D3b4963e4B675eC101928df));
        kiibaCoin = RevToken(address(0x3D4AA21e8915F3b5409BDb20f76457FCdAF8f757));
        seeroCoin = RevToken(address(0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6));

        // mooCoin.transfer(kiba, amount);
        // mooCoin.transfer(sero, amount);

        // kiibaCoin.transfer(kiba, amount);
        // kiibaCoin.transfer(sero, amount);

        // seeroCoin.transfer(kiba, amount);
        // seeroCoin.transfer(sero, amount);
        seeroCoin.transfer(craig, amount);
        

    }
        

}