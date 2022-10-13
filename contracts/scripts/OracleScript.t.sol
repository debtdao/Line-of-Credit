import {RevToken} from "../../contracts/mock/RevToken.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";

contract OracleScript is Script {

    SimpleOracle oracle;

    function run() public {

        vm.startBroadcast();
        oracle = SimpleOracle(address(0x0B3807b858B5fa24a39bced436DBc5A988Ca58d6));
        int256 price = oracle.getLatestAnswer(address(0x3D4AA21e8915F3b5409BDb20f76457FCdAF8f757));
        console.logInt(price);

        


    }

}