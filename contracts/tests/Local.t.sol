import {RevToken} from "../../contracts/mock/RevToken.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";
import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";
import {LineFactory} from "../modules/factories/LineFactory.sol";
import "forge-std/Test.sol";

contract LocalTest is Test { 

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
    uint constant MAX_INT = type(uint256).max;

    

    


    function test_createLineOfCredit_asBorrower() external {

        collateral_token = new RevToken('Collateral Token','COL');
        credit_token = new RevToken('Credit Token', 'CREDIT');

        // minitng tokens to the borrower (for collateral) and to lender (so they can provide credit)
        collateral_token.mint(borrower, mintAmount);
        credit_token.mint(lender, mintAmount);
        
        oracle = new SimpleOracle(address(collateral_token), address(credit_token));
    
        vm.startPrank(borrower);

        factory = LineFactory(address(0x43158693DBA386562F0581CD48E68dF027a5A877));
        address line_address = factory.deploySecuredLine(address(oracle), borrower, borrower, 90, payable(swapTarget));
        line = SecuredLine(payable(line_address));

        address escrow_address = address(line.escrow());
        escrow = Escrow(payable(escrow_address));


        collateral_token.approve(escrow_address, MAX_INT);
        escrow.enableCollateral(address(collateral_token));
        escrow.addCollateral(collateral_amount, address(collateral_token));

        // no token transfer happens here
        line.addCredit(2000, 1000, credit_amount, address(credit_token), address(lender));

        vm.stopPrank();

        vm.startPrank(lender);
        
       credit_token.approve(line_address, MAX_INT);
       // line.addCredit(2000, 1000, credit_amount, address(0), address(lender));
       line.addCredit(2000, 1000, credit_amount, address(credit_token), address(lender));

       // vm.stopPrank();

//
    }

}

/*
    forge test -m test_createLineOfCredit_asBorrower -vvvv 

*/

