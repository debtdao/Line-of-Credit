pragma solidity 0.8.9;
import { SpigotController } from "./Spigot.sol";
import { DSTest } from  "../lib/ds-test/src/test.sol";
import { CreditToken } from "./tokens/CreditToken.sol";
import { SimpleRevenueContract } from './mock/SimpleRevenueContract.sol';

contract SpigotTest is DSTest {
    // spigot contracts/configurations to test against
    CreditToken private token;
    SpigotController private spigotController;
    address private revenueContract;
    SpigotController.SpigotSettings private settings;

    // function signatures for mock revenue contract to pass as params to spigot
    bytes4 constant opsFunc = bytes4(keccak256("doAnOperationsThing()"));
    bytes4 constant claimPullPaymentFunc = bytes4(keccak256("claimPullPayment()"));
    bytes4 constant transferOwnerFunc = bytes4(keccak256("transferOwnership(address)"));
    
    // Mostly unused in tests so convenience for empty array
    bytes4[] private whitelist; 

    // Spigot Controller access control vars
    address private owner;
    address private operator = address(0xdead);
    address private treasury = address(0xdead);

    function setUp() public {
        owner = msg.sender; // this?
        token = new CreditToken(100*10**18, address(this));
        token.updateMinter(address(this), true);
        revenueContract = address(new SimpleRevenueContract(owner, address(token)));
        
        // TODO find some good revenue contracts to mock and deploy
    }

    /**
     * @dev Helper function to initialize new Spigots with different params to test functionality
     */
    function _initSpigot(
        address _token,
        uint8 split,
        bytes4 claimFunc,
        bytes4 newOwnerFunc,
        bytes4[] memory _whitelist
    ) internal {
        settings = SpigotController.SpigotSettings({
            token: address(_token),
            ownerSplit: split,
            claimFunction: claimFunc, // test push payments first
            transferOwnerFunction: newOwnerFunc
        });
        // create dynamic arrays for function args
        address[] memory c;
        c[0] = revenueContract;
        SpigotController.SpigotSettings[] memory s;
        s[0] = settings;

        spigotController = new SpigotController(owner, treasury, operator, c, s, _whitelist);
    }


    // Claiming functions

    function test_claimRevenue() public {

        // can only claim from predefined contracts
        // proper amount is dispersed/escrowed
    }

    function prove_claimEscrow(uint256 totalRevenue) public {

        // takes all tokens
        // tokens added to owner balance
    }

    function testFail_claimEscrowUnregisteredToken() public {
        // configure with proper token
        _initSpigot(address(token), 100, bytes4(0), transferOwnerFunc, whitelist);
         // send revenue and claim it
        CreditToken fakeToken = new CreditToken(1, address(this));
        fakeToken.updateMinter(address(this), true);
        fakeToken.mint(address(spigotController), 10**10);
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        // claim fails because escrowed == 0
        spigotController.claimEscrow(address(fakeToken));
    }

    function testFail_claimEscrowAsNonOwner() public {
        address oldOwner = owner;
        owner = address(0xdebf); // change owner of spigot to deploy
        _initSpigot(address(token), 100, bytes4(0), transferOwnerFunc, whitelist);
        owner = oldOwner; // Set owner back for other tests

        // send revenue and claim it
        token.mint(address(spigotController), 10**10);
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        // claim fails
        spigotController.claimEscrow(address(token));
    }


    // Payment splitting tests
    /**
     * @dev helper func to check revenue payment streams to `Owner` and `Treasury` happened and Spigot is accounting properly.
    */
    function _assertSpigotSplits(uint256 totalRevenue) internal {
        assertEq(
            spigotController.getEscrowData(address(token)),
            totalRevenue * settings.ownerSplit / 100,
            'Invalid escrow amount for spigot revenue'
        );
        
        assertEq(
            address(token) == address(0) ?
                address(spigotController).balance :
                token.balanceOf(address(spigotController)),
            totalRevenue * settings.ownerSplit / 100,
            'Spigot token holdings vs escrow amount mismatch'
        );

        assertEq(
            address(token) == address(0) ?
                address(treasury).balance :
                token.balanceOf(treasury),
            totalRevenue * (100 - settings.ownerSplit) / 100,
            'Invalid treasury payment amount for spigot revenue'
        );
    }

    function prove_pushPaymentTokenSpigotSplit(uint256 totalRevenue) public {
        _initSpigot(address(token), 100, bytes4(0), transferOwnerFunc, whitelist);

        token.mint(address(spigotController), totalRevenue);
        assertEq(token.balanceOf(address(spigotController)), totalRevenue);
        
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);

        _assertSpigotSplits(totalRevenue);
    }


    function prove_pullPaymentTokenSpigotSplit(uint256 totalRevenue) public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        
        token.mint(revenueContract, totalRevenue);
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        
        _assertSpigotSplits(totalRevenue);
        assertEq(token.balanceOf(revenueContract), 0, 'All revenue not siphoned into Spigot');
    }

    function prove_pushPaymentETHSpigotSplit(uint256 totalRevenue) public {
        _initSpigot(address(0), 100, bytes4(0), transferOwnerFunc, whitelist);
        
        payable(address(spigotController)).call{value: totalRevenue};
        assertEq(address(spigotController).balance, totalRevenue);
        
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        _assertSpigotSplits(totalRevenue);
    }

    function test_pullPaymentETHSpigotSplit(uint256 totalRevenue) public {
        _initSpigot(address(0), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        // spigot balance increases when claimFunction is called on revenue contract
    }

    // Spigot initialization

    function proveFail_addSpigot_OwnerSplitParam(uint8 split) public {
        if(split <= 100 && split > 0) {
            _initSpigot(address(token), split, claimPullPaymentFunc, transferOwnerFunc, whitelist);
            // fails when updating spigot that already has settings
            settings.ownerSplit = 0;
            spigotController.addSpigot(revenueContract, settings);
        } else {
            _initSpigot(address(token), split, bytes4(0), transferOwnerFunc, whitelist);
        }
    }
    
    function testFail_addSpigot_TransferFuncParam() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, bytes4(0), whitelist);
    }

    function prove_addSpigot_TransferFuncParam(bytes4 func) public {
        if(func != bytes4(0)) {
            _initSpigot(address(token), 100, claimPullPaymentFunc, func, whitelist);
        }
    }

}
