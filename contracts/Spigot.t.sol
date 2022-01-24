pragma solidity 0.8.9;
import { SpigotController } from "./Spigot.sol";
import { DSTest } from  "../lib/ds-test/src/test.sol";
import { CreditToken } from "./tokens/CreditToken.sol";
import { SimpleRevenueContract } from './mock/SimpleRevenueContract.sol';

contract SpigotTest is DSTest {
    // spigot contracts/configurations to test against
    CreditToken private token;
    address private revenueContract;
    SpigotController private spigotController;
    SpigotController.SpigotSettings private settings;

    // Handy named vars for common inputs
    address constant eth = address(0);
    uint256 constant MAX_REVENUE = type(uint).max / 100;
    // function signatures for mock revenue contract to pass as params to spigot
    bytes4 constant opsFunc = SimpleRevenueContract.doAnOperationsThing.selector;
    bytes4 constant transferOwnerFunc = SimpleRevenueContract.transferOwnership.selector;
    bytes4 constant claimPullPaymentFunc = SimpleRevenueContract.claimPullPayment.selector;
    bytes4 constant claimPushPaymentFunc = bytes4(0);

    // Mostly unused in tests so convenience for empty array
    bytes4[] private whitelist; 

    // Spigot Controller access control vars
    address private owner = address(this);
    address private operator = address(this);
    address private treasury = address(this);

    function setUp() public {
        token = new CreditToken(type(uint).max, address(this));
        token.updateMinter(address(this), true);
        revenueContract = address(new SimpleRevenueContract(owner, address(token)));
        token.updateWhitelist(address(revenueContract), true);
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
        settings = SpigotController.SpigotSettings(_token, split, claimFunc, newOwnerFunc);

        // create dynamic arrays for function args
        address[] memory c;
        SpigotController.SpigotSettings[] memory s;

        spigotController = new SpigotController(owner, treasury, operator, c, s, _whitelist);
        spigotController.addSpigot(revenueContract, settings);
        // giv spigot ownership to claim revenue
        revenueContract.call(abi.encodeWithSelector(newOwnerFunc, address(spigotController)));
        // let spigot interact with token
        token.updateWhitelist(address(spigotController), true);
    }


    // Claiming functions


    /**
     * @dev helper func to get max revenue payment claimable in Spigot
    */
    function getMaxRevenue(uint256 totalRevenue) internal returns(uint256) {
         // prevent overflow like in Spigot
        if(totalRevenue> MAX_REVENUE) totalRevenue = MAX_REVENUE;
        return totalRevenue;
    }

    function testFail_claimRevenue_PullPaymentNoTokenRevenue() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigotController.claimRevenue(revenueContract, claimData);
    }

    function testFail_claimRevenue_PushPaymentNoTokenRevenue() public {
        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
    }

    function testFail_claimRevenue_PushPaymentNoETHRevenue() public {
        _initSpigot(eth, 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
    }

    function testFail_claimRevenue_PullPaymentNoETHRevenue() public {
        _initSpigot(eth, 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigotController.claimRevenue(revenueContract, claimData);
    }

    /**
        @dev only need to test claim function on pull payments because push doesnt call revenue contract
     */
    function testFail_claimRevenue_NonExistantClaimFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(bytes4(0xdebfda05));
        spigotController.claimRevenue(revenueContract, claimData);
    }

    function testFail_claimRevenue_MaliciousClaimFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(transferOwnerFunc);
        spigotController.claimRevenue(revenueContract, claimData);
    }


    // Payment split accounting

    /**
     * @dev helper func to check revenue payment streams to `Owner` and `Treasury` happened and Spigot is accounting properly.
    */
    function assertSpigotSplits(uint256 totalRevenue) internal {
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

    function prove_claimRevenue_pushPaymentToken(uint256 totalRevenue) public {
        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        // send revenue token directly to spigot (push)
        token.mint(address(spigotController), totalRevenue);
        assertEq(token.balanceOf(address(spigotController)), totalRevenue);
        
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);

        assertSpigotSplits(getMaxRevenue(totalRevenue));
    }


    function prove_claimRevenue_pullPaymentToken(uint256 totalRevenue) public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        
        token.mint(revenueContract, totalRevenue);
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        
        assertSpigotSplits(getMaxRevenue(totalRevenue));
        assertEq(
            token.balanceOf(revenueContract),
            0,
            'All revenue not siphoned into Spigot'
        );
    }

    function prove_claimRevenue_pushPaymentETH(uint256 totalRevenue) public {
        _initSpigot(eth, 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);
        
        payable(address(spigotController)).call{value: totalRevenue};
        assertEq(address(spigotController).balance, totalRevenue);
        
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        assertSpigotSplits(getMaxRevenue(totalRevenue));
    }

    function prove_claimRevenue_pullPaymentETH(uint256 totalRevenue) public {
        _initSpigot(eth, 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        payable(revenueContract).call{value: totalRevenue}("");

        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        assertSpigotSplits(getMaxRevenue(totalRevenue));
    }

    function prove_claimRevenue_MaxRevenueClaim(uint256 totalRevenue) public {
        if(totalRevenue < MAX_REVENUE) return;
        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        token.mint(address(spigotController), totalRevenue);
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        
        assertEq(
            spigotController.getEscrowData(address(token)),
            MAX_REVENUE * settings.ownerSplit / 100,
            'Invalid escrow amount for spigot revenue'
        );
        
        assertGe(
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
            MAX_REVENUE * (100 - settings.ownerSplit) / 100,
            'Invalid treasury payment amount for spigot revenue'
        );

        assertEq(
            token.balanceOf(address(spigotController)),
            totalRevenue - getMaxRevenue(totalRevenue),
            'Error enforcing max revenue'
        );
    }

    // Failing cases
    function testFail_claimEscrow_AsNonOwner() public {
        address oldOwner = owner;
        owner = address(0xdebf); // change owner of spigot to deploy
        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);
        owner = oldOwner; // Set owner back for other tests

        // send revenue and claim it
        token.mint(address(spigotController), 10**10);
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        // claim fails
        spigotController.claimEscrow(address(token));
    }


    function testFail_claimEscrow_UnregisteredToken() public {
        // configure with proper token
        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);
         // send revenue and claim it
        CreditToken fakeToken = new CreditToken(1, address(this));
        fakeToken.updateMinter(address(this), true);
        fakeToken.mint(address(spigotController), 10**10);
        bytes memory claimData;
        spigotController.claimRevenue(revenueContract, claimData);
        // claim fails because escrowed == 0
        spigotController.claimEscrow(address(fakeToken));
    }

  
    // Spigot initialization
    function test_addSpigot_ProperSettings() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        (address _token, uint8 _split, bytes4 _claim, bytes4 _transfer) = spigotController.getSetting(revenueContract);

        assertEq(settings.token, _token);
        assertEq(settings.ownerSplit, _split);
        assertEq(settings.claimFunction, _claim);
        assertEq(settings.transferOwnerFunction, _transfer);
    }



    function prove_addSpigot_OwnerSplitParam(uint8 split) public {
        // Split can only be 0-100 for numerator in percent calculation
        if(split > 100 || split == 0) return;
        // emit log_named_uint("owner split", split);
        _initSpigot(address(token), split, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        // assertEq(spigotController.getSetting(revenueContract).ownerSplit, split);
    }

    function proveFail_addSpigot_OwnerSplitParam(uint8 split) public {
        // Split can only be 0-100 for numerator in percent calculation
        if(split <= 100 && split > 0) return;

        // emit log_named_uint("owner split", split);
        _initSpigot(address(token), split, claimPushPaymentFunc, transferOwnerFunc, whitelist);
    }
    
    function testFail_addSpigot_NoTransferFunc() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, bytes4(0), whitelist);
    }

    function prove_addSpigot_TransferFuncParam(bytes4 func) public {
        if(func == claimPushPaymentFunc) return;
        _initSpigot(address(token), 100, claimPullPaymentFunc, func, whitelist);

        (,,, bytes4 _transfer) = spigotController.getSetting(address(revenueContract));
        assertEq(_transfer, func);
    }

     function testFail_addSpigot_AsNonOwnerOrOperator() public {
        address oldOwner = owner;
        owner =  address(0xdebf);
        address oldOperator = operator;
        operator =  address(0xdebf);
        
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        owner = oldOwner;
        operator = oldOperator;

        spigotController.addSpigot(address(0xbeef), settings);
    }

    function testFail_addSpigot_ExistingSpigot() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        spigotController.addSpigot(revenueContract, settings);
    }

    function testFail_addSpigot_SpigotAsRevenueContract() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        spigotController.addSpigot(address(spigotController), settings);
    }

    // Operate()

    function testFail_operate_ClaimRevenueFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        
        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigotController.operate(revenueContract, claimData);
    }

    // Access Control Changes
    function test_updateOwner_AsOwner() public {
        address oldOwner = owner;
        owner =  address(this);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        owner = oldOwner;

        spigotController.updateOwner(address(0xbeef));
        assertEq(spigotController.getOwner(), address(0xbeef));

    }

    function test_updateOperator_AsOperator() public {
        address oldOperator = operator;
        operator =  address(this);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        operator = oldOperator;

        spigotController.updateOperator(address(0xbeef));
        assertEq(spigotController.getOperator(), address(0xbeef));
    }

    function test_updateTreasury_AsTreasury() public {
        address oldTreasury = treasury;
        treasury =  address(this);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        treasury = oldTreasury;

        spigotController.updateTreasury(address(0xbeef));
        assertEq(spigotController.getTreasury(), address(0xbeef));
    }

    function test_updateTreasury_AsOperator() public {
        address oldOperator = operator;
        operator =  address(this);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        operator = oldOperator;

        spigotController.updateTreasury(address(0xbeef));
        assertEq(spigotController.getTreasury(), address(0xbeef));
    }

    function testFail_updateOwner_AsNonOwner() public {
        address oldOwner = owner;
        owner =  address(0xdebf);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        owner = oldOwner;

        spigotController.updateOwner(address(this));
    }

    function testFail_updateOwner_NullAddress() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigotController.updateOwner(address(0));
    }
    function testFail_updateOperator_AsNonOperator() public {
        address oldOperator = operator;
        operator =  address(0xdebf);
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        operator = oldOperator;

        spigotController.updateOperator(address(this));
    }

    function testFail_updateOperator_NullAddress() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigotController.updateOperator(address(0));
    }

    function testFail_updateTreasury_AsNonTreasuryOrOperator() public {
        address oldTreasury = treasury;
        address oldOperator = operator;
        treasury =  address(0xdebf);
        operator =  address(0xdebf);

        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        
        treasury = oldTreasury;
        operator = oldOperator;

        spigotController.updateTreasury(address(this));
    }

    function testFail_updateTreasury_NullAddress() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        spigotController.updateTreasury(address(0));
    }
}
