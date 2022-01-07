import "../lib/ds-test/src/test.sol";
import "./Spigot.sol";
contract SpigotTest is DSTest {
    SpigotController spigotController;

    function setUp() public {
        spigotController = new SpigotController();
        // TODO find some good revenue contracts to mock and deploy
    }

    function test_pushPaymentToken() public {
        // spigot balance increases when token is sent directly
    }

    function test_pushPaymentETH() public {
        // spigot balance increases when ETH is sent directly
    }

    function test_pullPaymentToken(address revenueContract) public {
        // spigot balance increases when claimFunction is called on revenue contract 
    }
    
    function test_pullPaymentETH(address revenueContract) public {
        // spigot balance increases when claimFunction is called on revenue contract
    }

    function prove_claimRevenue(address revenueContract) public {
        // can only claim from predefined contracts
        // proper amount is dispersed/escrowed
    }

    function prove_claimEscrow(address token) public {
        // only registered tokens can be claimed
        // takes all tokens
        // tokens added to owner balance
    }

}
