pragma solidity 0.8.9;

import "forge-std/Test.sol";
import { Spigot } from "./Spigot.sol";

import { RevenueToken } from "../../mock/RevenueToken.sol";
import { SimpleRevenueContract } from '../../mock/SimpleRevenueContract.sol';
import { ISpigot } from '../../interfaces/ISpigot.sol';

contract SpigotTest is Test {
    // spigot contracts/configurations to test against
    RevenueToken private token;
    address private revenueContract;
    Spigot private spigot;
    ISpigot.Setting private settings;

    // Named vars for common inputs
    address constant eth = address(0);
    uint256 constant MAX_REVENUE = type(uint).max / 100;
    // function signatures for mock revenue contract to pass as params to spigot
    bytes4 constant opsFunc = SimpleRevenueContract.doAnOperationsThing.selector;
    bytes4 constant transferOwnerFunc = SimpleRevenueContract.transferOwnership.selector;
    bytes4 constant claimPullPaymentFunc = SimpleRevenueContract.claimPullPayment.selector;
    bytes4 constant claimPushPaymentFunc = bytes4(0);

    // create dynamic arrays for function args
    // Mostly unused in tests so convenience for empty array
    bytes4[] private whitelist;
    address[] private c;
    ISpigot.Setting[] private s;

    // Spigot Controller access control vars
    address private owner;
    address private operator;
    address private treasury;

    function setUp() public {
        owner = address(this);
        operator = address(this);
        treasury = address(0xf1c0);
        token = new RevenueToken();

        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

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
        // deploy new revenue contract with settings
        revenueContract = address(new SimpleRevenueContract(address(this), _token));

        settings = ISpigot.Setting(_token, split, claimFunc, newOwnerFunc);
       
        spigot = new Spigot(owner, treasury, operator);
        
        // add spigot for revenue contract 
        require(spigot.addSpigot(revenueContract, settings), "Failed to add spigot");

        // give spigot ownership to claim revenue
        revenueContract.call(abi.encodeWithSelector(newOwnerFunc, address(spigot)));
    }


    // Claiming functions

    function test_claimRevenue_PullPaymentNoTokenRevenue() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, claimData);
    }

    function test_claimRevenue_PushPaymentNoTokenRevenue() public {
        _initSpigot(address(token), 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData;
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, claimData);
    }

    function test_claimRevenue_PushPaymentNoETHRevenue() public {
        _initSpigot(eth, 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData;
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, claimData);
    }

    function test_claimRevenue_PullPaymentNoETHRevenue() public {
        _initSpigot(eth, 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, claimData);
    }

    /**
        @dev only need to test claim function on pull payments because push doesnt call revenue contract
     */
    function test_claimRevenue_NonExistantClaimFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(bytes4(0xdebfda05));
        vm.expectRevert(ISpigot.BadFunction.selector);
        spigot.claimRevenue(revenueContract, claimData);
    }

    function test_claimRevenue_MaliciousClaimFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        bytes memory claimData = abi.encodeWithSelector(transferOwnerFunc);
        vm.expectRevert(ISpigot.BadFunction.selector);
        spigot.claimRevenue(revenueContract, claimData);
    }


    // Claim Revenue - payment split and escrow accounting

    /**
     * @dev helper func to get max revenue payment claimable in Spigot.
     *      Prevents uint overflow on owner split calculations
    */
    function getMaxRevenue(uint256 totalRevenue) internal pure returns(uint256, uint256) {
        if(totalRevenue> MAX_REVENUE) return(MAX_REVENUE, totalRevenue - MAX_REVENUE);
        return (totalRevenue, 0);
    }

    /**
     * @dev helper func to check revenue payment streams to `owner` and `treasury` happened and Spigot is accounting properly.
    */
    function assertSpigotSplits(address _token, uint256 totalRevenue) internal {
        (uint256 maxRevenue, uint256 overflow) = getMaxRevenue(totalRevenue);
        uint256 escrowed = maxRevenue * settings.ownerSplit / 100;

        assertEq(
            spigot.getEscrowed(_token),
            escrowed,
            'Invalid escrow amount for spigot revenue'
        );

        assertEq(
            _token == eth ?
                address(spigot).balance :
                RevenueToken(token).balanceOf(address(spigot)),
            escrowed + overflow, // revenue over max stays in contract unnaccounted
            'Spigot balance vs escrow + overflow mismatch'
        );

        assertEq(
            _token == eth ?
                address(treasury).balance :
                RevenueToken(token).balanceOf(treasury),
            maxRevenue - escrowed,
            'Invalid treasury payment amount for spigot revenue'
        );
    }

    function test_claimRevenue_pushPaymentToken(uint256 totalRevenue) public {
        if(totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;

        // send revenue token directly to spigot (push)
        token.mint(address(spigot), totalRevenue);
        assertEq(token.balanceOf(address(spigot)), totalRevenue);
        
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);

        assertSpigotSplits(address(token), totalRevenue);
    }

    function test_claimRevenue_pullPaymentToken(uint256 totalRevenue) public {
        if(totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        
        token.mint(revenueContract, totalRevenue); // send revenue
        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigot.claimRevenue(revenueContract, claimData);
        
        assertSpigotSplits(address(token), totalRevenue);
        assertEq(token.balanceOf(revenueContract), 0, 'All revenue not siphoned into Spigot');
    }

    /**
     * @dev
     @param totalRevenue - uint96 because that is max ETH in this testing address when dapptools initializes
     */
    function test_claimRevenue_pushPaymentETH(uint96 totalRevenue) public {
        if(totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;
        _initSpigot(eth, 100, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        payable(address(spigot)).transfer(totalRevenue);
        assertEq(totalRevenue, address(spigot).balance); // ensure spigot received revenue
        
        bytes memory claimData;
        uint256 revenueClaimed = spigot.claimRevenue(revenueContract, claimData); 
        assertEq(totalRevenue, revenueClaimed, 'Improper revenue amount claimed');
        emit log_named_uint("escrowdAmount", spigot.getEscrowed(eth));

        
        assertSpigotSplits(eth, totalRevenue);
    }

    function test_claimRevenue_pullPaymentETH(uint96 totalRevenue) public {
        if(totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;
        _initSpigot(eth, 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

        payable(revenueContract).transfer(totalRevenue);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        assertEq(totalRevenue, spigot.claimRevenue(revenueContract, claimData), 'invalid revenue amount claimed');

        assertSpigotSplits(eth, totalRevenue);
    }

    
    // Claim escrow 

    function test_claimEscrow_AsOwner(uint256 totalRevenue) public {
        if(totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;
        // send revenue and claim it
        token.mint(address(spigot), totalRevenue);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);
        assertSpigotSplits(address(token), totalRevenue);

        uint256 claimed = spigot.claimEscrow(address(token));
        (uint256 maxRevenue,) = getMaxRevenue(totalRevenue);

        assertEq(maxRevenue * settings.ownerSplit / 100, claimed, "Invalid escrow claimed");
        assertEq(token.balanceOf(owner), claimed, "Claimed escrow not sent to owner");
    }

    function test_claimEscrow_AsNonOwner() public {
        // send revenue and claim it
        token.mint(address(spigot), 10**10);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);

        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);

        // claim fails
        spigot.claimEscrow(address(token));
    }

    function test_claimEscrow_UnclaimedRevenue() public {
        // send revenue and claim it
        token.mint(address(spigot), MAX_REVENUE + 1);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData);
        
        vm.expectRevert(ISpigot.UnclaimedRevenue.selector);
        spigot.claimEscrow(address(token));       // reverts because excess tokens
    }

    function test_claimEscrow_AllRevenueClaimed() public {
        // send revenue and claim it
        token.mint(address(spigot), MAX_REVENUE + 1);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, claimData); // collect majority of revenue
        spigot.claimRevenue(revenueContract, claimData); // collect remained

        spigot.claimEscrow(address(token));       // should pass bc no unlciamed revenue
    }

    function test_claimEscrow_UnregisteredToken() public {
        // create new token and send push payment
        RevenueToken fakeToken = new RevenueToken();
        fakeToken.mint(address(spigot), 10**10);

        bytes memory claimData;
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, claimData);
        
        // will always return 0 if you can't claim revenue for token
        // spigot.claimEscrow(address(fakeToken));
    }

  
    
    // Spigot initialization
    

    function test_addSpigot_ProperSettings() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        (address _token, uint8 _split, bytes4 _claim, bytes4 _transfer) = spigot.getSetting(revenueContract);

        assertEq(settings.token, _token);
        assertEq(settings.ownerSplit, _split);
        assertEq(settings.claimFunction, _claim);
        assertEq(settings.transferOwnerFunction, _transfer);
    }

    function test_addSpigot_OwnerSplit0To100(uint8 split) public {
        // Split can only be 0-100 for numerator in percent calculation
        if(split > 100 || split == 0) return;
        // emit log_named_uint("owner split", split);
        _initSpigot(address(token), split, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        // assertEq(spigot.getSetting(revenueContract).ownerSplit, split);
    }

    function test_addSpigot_NoOwnerSplitOver100(uint8 split) public {
        // Split can only be 0-100 for numerator in percent calculation
        if(split <= 100) return;

        revenueContract = address(new SimpleRevenueContract(address(this), address(token)));

        settings = ISpigot.Setting(address(token), split, claimPushPaymentFunc, transferOwnerFunc);
      
        vm.expectRevert(ISpigot.BadSetting.selector);

        spigot.addSpigot(address(revenueContract), settings);
    }
    
    function test_addSpigot_NoTransferFunc() public {
        revenueContract = address(new SimpleRevenueContract(address(this), address(token)));

        settings = ISpigot.Setting(address(token), 100, claimPullPaymentFunc, bytes4(0));
      
        vm.expectRevert(ISpigot.BadSetting.selector);

        spigot.addSpigot(address(revenueContract), settings);
    }

    function test_addSpigot_TransferFuncParam(bytes4 func) public {
        if(func == claimPushPaymentFunc) return;
        _initSpigot(address(token), 100, claimPushPaymentFunc, func, whitelist);

        (,,, bytes4 _transfer) = spigot.getSetting(address(revenueContract));
        assertEq(_transfer, func);
    }

     function test_addSpigot_AsNonOwner() public {
        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.addSpigot(address(0xdebf), settings);
    }

    function test_addSpigot_ExistingSpigot() public {
        vm.expectRevert();
        spigot.addSpigot(revenueContract, settings);
    }

    function test_addSpigot_SpigotAsRevenueContract() public {
        vm.expectRevert();
        spigot.addSpigot(address(spigot), settings);
    }


    //  Updating
    function test_updateOwnerSplit_AsOwner() public {
        spigot.updateOwnerSplit(revenueContract, 0);
    }

    function test_updateOwnerSplit_0To100(uint8 split) public {
        if(split > 100) return;
        assertTrue(spigot.updateOwnerSplit(revenueContract, split));
        (,uint8 split_,,) = spigot.getSetting(revenueContract);
        assertEq(split, split_);
    }

    function testFail_updateOwnerSplit_AsNonOwner() public {
        hoax(address(0xdebf));
        spigot.updateOwnerSplit(revenueContract, 0);
    }

    function test_updateOwnerSplit_Over100(uint8 split) public {
        if(split <= 100) return;
        vm.expectRevert(ISpigot.BadSetting.selector);
        spigot.updateOwnerSplit(revenueContract, split);
    }

    function test_updateOwnerSplit_UnclaimedRevenue() public {
        // send revenue and dont claim
        token.mint(address(spigot), type(uint).max);
        vm.expectRevert(ISpigot.UnclaimedRevenue.selector);
        spigot.updateOwnerSplit(revenueContract, 0);     // reverts because excess tokens
    }


    // Operate()

    function test_operate_NonWhitelistedFunction() public {
        assertTrue(spigot.updateWhitelistedFunction(opsFunc, false));
        vm.expectRevert(ISpigot.BadFunction.selector);
        spigot.operate(revenueContract, abi.encodeWithSelector(opsFunc));
    }

    function test_operate_OperatorCanOperate() public {
        assertTrue(spigot.updateWhitelistedFunction(opsFunc, true));
        assertTrue(spigot.operate(revenueContract, abi.encodeWithSelector(opsFunc)));
    }

    function test_operate_ClaimRevenueFunction() public {
        _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
        
        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        vm.expectRevert(ISpigot.BadFunction.selector);
        spigot.operate(revenueContract, claimData);
    }
    

    function test_operate_AsNonOperator() public {
        hoax(address(0xdebf));
        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.operate(revenueContract, claimData);
    }


     function test_operate_NonWhitelistFunc() public {
        vm.expectRevert(ISpigot.BadFunction.selector);
        spigot.operate(revenueContract, abi.encodeWithSelector(opsFunc));
    }

    function test_updateWhitelistedFunction_ToTrue() public {
        assertTrue(spigot.updateWhitelistedFunction(opsFunc, true));
        assertTrue(spigot.isWhitelisted(opsFunc));
    }

    function test_updateWhitelistedFunction_ToFalse() public {
        assertTrue(spigot.updateWhitelistedFunction(opsFunc, false));
        assertFalse(spigot.isWhitelisted(opsFunc));
    }

    // Release

    function test_removeSpigot() public {
        (address token_,,,) = spigot.getSetting(revenueContract);
        assertEq(address(token), token_);

        spigot.removeSpigot(revenueContract);

        (address token__,,,) = spigot.getSetting(revenueContract);
        assertEq(address(0), token__);
    }


    function test_removeSpigot_AsOperator() public {
        spigot.updateOwner(address(0xdebf)); // random owner
        
        assertEq(spigot.owner(), address(0xdebf));
        assertEq(spigot.operator(), address(this));

        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.removeSpigot(revenueContract);
    }

    function testFail_removeSpigot_AsNonOwner() public {
        hoax(address(0xdebf));
        spigot.removeSpigot(revenueContract);
    }

    function test_removeSpigot_UnclaimedRevenue() public {
        // send revenue and dont claim
        token.mint(address(spigot), type(uint).max);
        vm.expectRevert(ISpigot.UnclaimedRevenue.selector);
        spigot.claimEscrow(address(token));       // reverts because excess tokens
    }


    // Access Control Changes
    function test_updateOwner_AsOwner() public {
        spigot.updateOwner(address(0xdebf));
        assertEq(spigot.owner(), address(0xdebf));
    }

    function test_updateOperator_AsOperator() public {
        spigot.updateOperator(address(0xdebf));
        assertEq(spigot.operator(), address(0xdebf));
    }

    function test_updateTreasury_AsTreasury() public {
        hoax(treasury);
        spigot.updateTreasury(address(0xdebf));
        assertEq(spigot.treasury(), address(0xdebf));
    }

    function test_updateTreasury_AsOperator() public {
        spigot.updateTreasury(address(0xdebf));
        assertEq(spigot.treasury(), address(0xdebf));
    }

    function test_updateOwner_AsNonOwner() public {
        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.updateOwner(address(this));
    }

    function test_updateOwner_NullAddress() public {
        vm.expectRevert();
        spigot.updateOwner(address(0));
    }

    function test_updateOperator_AsNonOperator() public {
        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.updateOperator(address(this));
    }

    function test_updateOperator_NullAddress() public {
        vm.expectRevert();
        spigot.updateOperator(address(0));
    }

    function test_updateTreasury_AsNonTreasuryOrOperator() public {
        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.updateTreasury(address(this));
    }

    function test_updateTreasury_NullAddress() public {
        hoax(treasury);
        vm.expectRevert();
        spigot.updateTreasury(address(0));
    }
}
