import {RevToken} from "../../contracts/mock/RevToken.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";
import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";
import {LineFactory} from "../modules/factories/LineFactory.sol";


/*
    // LENDER
{
  signerAddress: '0x0F9A106E70AF3D40A0CCc654f643033be9a6d29D',
  pvtKeyString: '2c3d69142a730eed0002cb57eaf416028d18dd7807a87025f718192b4f225cc9'
}


// ADMIN
{
  signerAddress: '0xa1f782d36A6EDEa1958a87a08B2E8E528FFa5E8c',
  pvtKeyString: '2b5c644a64d31206a1765413a261ad122943f54e3e0df6f7987f6e71f77a013f'
}
*/

contract LocalScript is Script {
    
    RevToken collateral_token;
    RevToken credit_token;

    // a mock price oracle (to compare price of collatoral to price of credit)
    SimpleOracle oracle;

    // Already exists
    LineFactory factory;

    // Deployed via Factory
    SecuredLine line;
    Escrow escrow;

    address borrower = 0xf44B95991CaDD73ed769454A03b3820997f00873;
    address lender = 0x0F9A106E70AF3D40A0CCc654f643033be9a6d29D;
    uint mintAmount = 1000000000 ether; // 100,000,000 tokens
    uint collateral_amount = 600000000 ether; // 60,000,000 tokens
    uint credit_amount = 100000000 ether; // 10,000,000
    address swapTarget = 0xcb7b9188aDA88Cb0c991C807acc6b44097059DEc; // exchange for swapping revenue tokens for credit tokens
    uint constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935; // could also use => type(uint256).max;
    // A
    

    function run() external {

        // Deploy contracts as deployer
        uint256 deployerPrivateKey= vm.envUint("DEPLOYER_KEY");
        uint256 lenderPrivateKey = vm.envUint("LENDER_KEY");
        uint256 borrowerPrivateKey = vm.envUint("BORROWER_KEY");

        vm.startBroadcast(deployerPrivateKey);


        // deploying new tokens to use as collateral and credit
        collateral_token = new RevToken('Collateral Token','COL');
        credit_token = new RevToken('Credit Token', 'CREDIT');

        // minitng tokens to the borrower (for collateral) and to lender (so they can provide credit)
        collateral_token.mint(borrower, mintAmount);
        credit_token.mint(lender, mintAmount);
        
        oracle = new SimpleOracle(address(collateral_token), address(credit_token));
        
        vm.stopBroadcast();


        // ============== BORROWER
        vm.startBroadcast(borrowerPrivateKey);

        factory = LineFactory(address(0xc23b896F2b4aE3E6362B0D536113Fa2F0C9b8886));
        address line_address = factory.deploySecuredLine(address(oracle), borrower, borrower, 90, payable(swapTarget));
        line = SecuredLine(payable(line_address)); // interface to securedLine at address x

        address escrow_address = address(line.escrow());
        escrow = Escrow(payable(escrow_address));


        collateral_token.approve(escrow_address, MAX_INT);
        escrow.enableCollateral(address(collateral_token));
        escrow.addCollateral(collateral_amount, address(collateral_token));

        // no token transfer happens here
        line.addCredit(2000, 1000, credit_amount, address(credit_token), address(lender));



        vm.stopBroadcast();
        
        
        // ============== LENDER
        vm.startBroadcast(lenderPrivateKey);

        credit_token.approve(line_address, MAX_INT);
        line.addCredit(2000, 1000, credit_amount, address(credit_token), address(lender));

        vm.stopBroadcast();




    }
}