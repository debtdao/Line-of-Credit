pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {Spigot} from "../modules/spigot/Spigot.sol";

import {SpigotLib} from "../utils/SpigotLib.sol";

import {RevenueToken} from "../mock/RevenueToken.sol";
import {SimpleRevenueContract} from "../mock/SimpleRevenueContract.sol";
import {Denominations} from "chainlink/Denominations.sol";

import {ISpigot} from "../interfaces/ISpigot.sol";

contract SpigotTest is Test {
   
    // spigot contracts/configurations to test against
    RevenueToken private token;
    address private revenueContract;
    Spigot private spigot;
    ISpigot.Setting private settings;

    // Named vars for common inputs
    uint256 constant MAX_REVENUE = type(uint256).max / 100;
    // function signatures for mock revenue contract to pass as params to spigot
    bytes4 constant opsFunc =
        SimpleRevenueContract.doAnOperationsThing.selector;
    bytes4 constant transferOwnerFunc =
        SimpleRevenueContract.transferOwnership.selector;
    bytes4 constant claimPullPaymentFunc =
        SimpleRevenueContract.claimPullPayment.selector;
    bytes4 constant claimPushPaymentFunc = bytes4(0);

    // create dynamic arrays for function args
    // Mostly unused in tests so convenience for empty array
    bytes4[] private whitelist;
    address[] private c;
    ISpigot.Setting[] private s;

    // Spigot Controller access control vars
    address private owner;
    address private operator;
  

    function setUp() public {
        owner = address(this);
        operator = address(10);
        
        token = new RevenueToken();

        _initSpigot(
            address(token),
            100,
            claimPushPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

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
        revenueContract = address(new SimpleRevenueContract(owner, _token));

        settings = ISpigot.Setting(split, claimFunc, newOwnerFunc);

        spigot = new Spigot(owner, operator);

        // add spigot for revenue contract
        require(
            spigot.addSpigot(revenueContract, settings),
            "Failed to add spigot"
        );

        // give spigot ownership to claim revenue
        revenueContract.call(
            abi.encodeWithSelector(newOwnerFunc, address(spigot))
        );
    }

    // Claiming functions

    function test_claimRevenue_PullPaymentNoTokenRevenue() public {
        _initSpigot(
            address(token),
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, address(token), claimData);
    }

    function test_claimRevenue_PushPaymentNoTokenRevenue() public {
        _initSpigot(
            address(token),
            100,
            claimPushPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        bytes memory claimData;
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, address(token), claimData);
    }

    function test_claimRevenue_PushPaymentNoETHRevenue() public {
        _initSpigot(
            Denominations.ETH,
            100,
            claimPushPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        bytes memory claimData;
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, address(token), claimData);
    }

    function test_claimRevenue_PullPaymentNoETHRevenue() public {
        _initSpigot(
            Denominations.ETH,
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, address(token), claimData);
    }

    /**
        @dev only need to test claim function on pull payments because push doesnt call revenue contract
     */
    function test_claimRevenue_NonExistantClaimFunction() public {
        _initSpigot(
            address(token),
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        bytes memory claimData = abi.encodeWithSelector(bytes4(0xdebfda05));
        vm.expectRevert(ISpigot.BadFunction.selector);
        spigot.claimRevenue(revenueContract, address(token), claimData);
    }

    function test_claimRevenue_MaliciousClaimFunction() public {
        _initSpigot(
            address(token),
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        bytes memory claimData = abi.encodeWithSelector(transferOwnerFunc);
        vm.expectRevert(ISpigot.BadFunction.selector);
        spigot.claimRevenue(revenueContract, address(token), claimData);
    }

    // Claim Revenue - payment split and escrow accounting

    /**
     * @dev helper func to get max revenue payment claimable in Spigot.
     *      Prevents uint overflow on owner split calculations
    */
    function getMaxRevenue(uint256 totalRevenue) internal pure returns(uint256, uint256) {
        if(totalRevenue > MAX_REVENUE) return(MAX_REVENUE, totalRevenue - MAX_REVENUE);
        return (totalRevenue, 0);
    }

    /**
     * @dev helper func to check revenue payment streams to `ownerTokens` and `operatorTokens` happened and Spigot is accounting properly.
    */
    function assertSpigotSplits(address _token, uint256 totalRevenue) internal {
        (uint256 maxRevenue, uint256 overflow) = getMaxRevenue(totalRevenue);
        uint256 ownerTokens = maxRevenue * settings.ownerSplit / 100;
        uint256 operatorTokens = maxRevenue - ownerTokens;
        uint256 spigotBalance = _token == Denominations.ETH ?
            address(spigot).balance :
            RevenueToken(_token).balanceOf(address(spigot));

        uint roundingFix = spigotBalance - (ownerTokens + operatorTokens);

        assertEq(roundingFix > 1, false);
        assertEq(
            spigot.getOwnerTokens(_token),
            ownerTokens,
            'Invalid escrow amount for spigot revenue'
        );

        assertEq(
            spigotBalance,
            ownerTokens + operatorTokens + roundingFix, // revenue over max stays in contract unnaccounted
            'Spigot balance vs escrow + overflow mismatch'
        );

        assertEq(
            spigot.getOperatorTokens(_token),
            maxRevenue - ownerTokens,
            'Invalid treasury payment amount for spigot revenue'
        );
    }

    function test_claimRevenue_pushPaymentToken(uint256 totalRevenue) public {
        if (totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;

        // send revenue token directly to spigot (push)
        token.mint(address(spigot), totalRevenue);
        assertEq(token.balanceOf(address(spigot)), totalRevenue);

        bytes memory claimData;
        spigot.claimRevenue(revenueContract, address(token), claimData);

        assertSpigotSplits(address(token), totalRevenue);
    }

    function test_claimRevenue_fails_on_contract_with_no_settings(uint256 totalRevenue) public {
        if (totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;

        // send revenue token directly to spigot (push)
        token.mint(address(spigot), totalRevenue);
        assertEq(token.balanceOf(address(spigot)), totalRevenue);

        bytes memory claimData;
        vm.expectRevert(ISpigot.InvalidRevenueContract.selector);
        spigot.claimRevenue(address(0), address(token), claimData);

        vm.expectRevert(ISpigot.InvalidRevenueContract.selector);
        spigot.claimRevenue(makeAddr("villain"), address(token), claimData);
    }

    function test_claimRevenue_pullPaymentToken(uint256 totalRevenue) public {
        if (totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;
        _initSpigot(
            address(token),
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        token.mint(revenueContract, totalRevenue); // send revenue
        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        spigot.claimRevenue(revenueContract, address(token), claimData);

        assertSpigotSplits(address(token), totalRevenue);
        assertEq(
            token.balanceOf(revenueContract),
            0,
            "All revenue not siphoned into Spigot"
        );
    }

    /**
     * @dev
     @param totalRevenue - uint96 because that is max ETH in this testing address when dapptools initializes
     */
    function test_claimRevenue_pushPaymentETH(uint96 totalRevenue) public {
        if (totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;
        _initSpigot(
            Denominations.ETH,
            100,
            claimPushPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        vm.deal((address(spigot)), totalRevenue);
        assertEq(totalRevenue, address(spigot).balance); // ensure spigot received revenue

        bytes memory claimData;
        uint256 revenueClaimed = spigot.claimRevenue(
            revenueContract,
            Denominations.ETH,
            claimData
        );
        assertEq(
            totalRevenue,
            revenueClaimed,
            "Improper revenue amount claimed"
        );

        assertSpigotSplits(Denominations.ETH, totalRevenue);
    }

    function test_claimRevenue_pullPaymentETH(uint96 totalRevenue) public {
        if (totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;
        _initSpigot(
            Denominations.ETH,
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        vm.deal(revenueContract, totalRevenue);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        assertEq(
            totalRevenue,
            spigot.claimRevenue(revenueContract, Denominations.ETH, claimData),
            "invalid revenue amount claimed"
        );

        assertSpigotSplits(Denominations.ETH, totalRevenue);
    }

    function test_claimRevenue_pushPaymentMultipleTokensPerContract(
        uint96 tokenRevenue,
        uint96 ethRevenue
    ) public {
        if (tokenRevenue == 0 || tokenRevenue > MAX_REVENUE) return;
        if (ethRevenue == 0 || ethRevenue > MAX_REVENUE) return;

        _initSpigot(
            Denominations.ETH,
            100,
            claimPushPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        deal(address(spigot), ethRevenue);
        deal(address(token), address(spigot), tokenRevenue);

        bytes memory claimData = abi.encodeWithSelector(claimPushPaymentFunc);
        assertEq(
            ethRevenue,
            spigot.claimRevenue(revenueContract, Denominations.ETH, claimData),
            "invalid revenue amount claimed"
        );
        assertEq(
            tokenRevenue,
            spigot.claimRevenue(revenueContract, address(token), claimData),
            "invalid revenue amount claimed"
        );

        assertSpigotSplits(Denominations.ETH, ethRevenue);
        assertSpigotSplits(address(token), tokenRevenue);
    }

    // function test_claimRevenue_pullPaymentMultipleTokensPerContract(uint96 tokenRevenue, uint96 ethRevenue) public {
    //     if(tokenRevenue == 0 || tokenRevenue > MAX_REVENUE) return;
    //     if(ethRevenue == 0 || ethRevenue > MAX_REVENUE) return;

    //     _initSpigot(Denominations.ETH, 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);
    //     _initSpigot(address(token), 100, claimPullPaymentFunc, transferOwnerFunc, whitelist);

    //     deal(revenueContract, ethRevenue);
    //     deal(address(token), revenueContract, tokenRevenue);

    //     bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
    //     assertEq(ethRevenue, spigot.claimRevenue(revenueContract, Denominations.ETH, claimData), 'invalid revenue amount claimed');
    //     assertEq(tokenRevenue, spigot.claimRevenue(revenueContract, address(token), claimData), 'invalid revenue amount claimed');

    //     assertSpigotSplits(Denominations.ETH, ethRevenue);
    //     assertSpigotSplits(address(token), tokenRevenue);
    // }

    // Claim escrow

    function test_claimOwnerTokens_AsOwner(uint256 totalRevenue) public {
        if(totalRevenue == 0 || totalRevenue > MAX_REVENUE) return;
        // send revenue and claim it
        token.mint(address(spigot), totalRevenue);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, address(token), claimData);
        assertSpigotSplits(address(token), totalRevenue);

        uint256 claimed = spigot.claimOwnerTokens(address(token));
        (uint256 maxRevenue,) = getMaxRevenue(totalRevenue);

        assertEq(
            (maxRevenue * settings.ownerSplit) / 100,
            claimed,
            "Invalid escrow claimed"
        );
        assertEq(
            token.balanceOf(owner),
            claimed,
            "Claimed escrow not sent to owner"
        );
    }

    function test_claimOwnerTokens_AsNonOwner() public {
        // send revenue and claim it
        token.mint(address(spigot), 10**10);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, address(token), claimData);

        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);

        // claim fails
        spigot.claimOwnerTokens(address(token));
    }

    function test_claimOperatorTokens_AsOperator(uint256 totalRevenue, uint8 _split) public {
        if(totalRevenue <= 50|| totalRevenue > MAX_REVENUE) return;
        if (_split > 99 || _split < 0) return;
        
        uint256 ownerTokens = totalRevenue * settings.ownerSplit / 100;
  

        

        _initSpigot(address(token), _split, claimPushPaymentFunc, transferOwnerFunc, whitelist);

        // console.log(settings.ownerSplit);
        // console.log(totalRevenue);
        
        
        // send revenue and claim it
        token.mint(address(spigot), totalRevenue);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, address(token), claimData);

        uint256 operatorTokens = spigot.getOperatorTokens(address(token));
        
        
        
        assertSpigotSplits(address(token), totalRevenue);
        

        vm.prank(operator);
        uint256 claimed = spigot.claimOperatorTokens(address(token));
        (uint256 maxRevenue,) = getMaxRevenue(totalRevenue);




       // assertEq(roundingFix > 1, false, "rounding fix is greater than 1");
        assertEq(operatorTokens  , claimed, "Invalid escrow claimed");
        assertEq(token.balanceOf(operator), claimed, "Claimed escrow not sent to owner");
    }

    function test_claimOperatorTokens_AsNonOperator() public {
        // send revenue and claim it
        token.mint(address(spigot), 10**10);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, address(token), claimData);

        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);

        // claim fails
        spigot.claimOperatorTokens(address(token));
    }

    // Unclaimed Revenue no longer affectbs Spigot behaviour. Keep for docs
    function test_claimEscrow_UnclaimedRevenue() public {
        // send revenue and claim it
        // token.mint(address(spigot), MAX_REVENUE + 1);
        // bytes memory claimData;
        // spigot.claimRevenue(revenueContract, address(token), claimData);
        // vm.expectRevert(ISpigot.UnclaimedRevenue.selector);
        // spigot.claimEscrow(address(token));       // reverts because excess tokens
    }

    function test_claimOwnerTokens_AllRevenueClaimed() public {
        // send revenue and claim it
        token.mint(address(spigot), MAX_REVENUE + 1);
        bytes memory claimData;
        spigot.claimRevenue(revenueContract, address(token), claimData); // collect majority of revenue
        spigot.claimRevenue(revenueContract, address(token), claimData); // collect remained

        spigot.claimOwnerTokens(address(token));       // should pass bc no unlciamed revenue
    }

    function test_claimEscrow_UnregisteredToken() public {
        // create new token and send push payment
        RevenueToken fakeToken = new RevenueToken();
        fakeToken.mint(address(spigot), 10**10);

        bytes memory claimData;
        vm.expectRevert(ISpigot.NoRevenue.selector);
        spigot.claimRevenue(revenueContract, address(token), claimData);

        // will always return 0 if you can't claim revenue for token
        // spigot.claimEscrow(address(fakeToken));
    }

    // Spigot initialization

    function test_addSpigot_ProperSettings() public {
        _initSpigot(
            address(token),
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );
        (uint8 _split, bytes4 _claim, bytes4 _transfer) = spigot.getSetting(
            revenueContract
        );

        // assertEq(settings.token, _token);
        assertEq(settings.ownerSplit, _split);
        assertEq(settings.claimFunction, _claim);
        assertEq(settings.transferOwnerFunction, _transfer);
    }

    function test_addSpigot_OwnerSplit0To100(uint8 split) public {
        // Split can only be 0-100 for numerator in percent calculation
        if (split > 100 || split == 0) return;
        _initSpigot(
            address(token),
            split,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );
        // assertEq(spigot.getSetting(revenueContract).ownerSplit, split);
    }

    function test_addSpigot_NoOwnerSplitOver100(uint8 split) public {
        // Split can only be 0-100 for numerator in percent calculation
        if (split <= 100) return;

        revenueContract = address(
            new SimpleRevenueContract(address(this), address(token))
        );

        settings = ISpigot.Setting(
            split,
            claimPushPaymentFunc,
            transferOwnerFunc
        );

        vm.expectRevert(ISpigot.BadSetting.selector);

        spigot.addSpigot(address(revenueContract), settings);
    }

    function test_addSpigot_NoTransferFunc() public {
        revenueContract = address(
            new SimpleRevenueContract(address(this), address(token))
        );

        settings = ISpigot.Setting(100, claimPullPaymentFunc, bytes4(0));

        vm.expectRevert(ISpigot.BadSetting.selector);

        spigot.addSpigot(address(revenueContract), settings);
    }

    function test_addSpigot_TransferFuncParam(bytes4 func) public {
        if (func == claimPushPaymentFunc) return;
        _initSpigot(address(token), 100, claimPushPaymentFunc, func, whitelist);

        (, , bytes4 _transfer) = spigot.getSetting(address(revenueContract));
        assertEq(_transfer, func);
    }

    function test_addSpigot_AsNonOwner() public {
        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.addSpigot(address(0xdebf), settings);
    }

    function test_addSpigot_ExistingSpigot() public {
        vm.expectRevert(SpigotLib.SpigotSettingsExist.selector);
        spigot.addSpigot(revenueContract, settings);
    }

    function test_addSpigot_SpigotAsRevenueContract() public {
        vm.expectRevert(SpigotLib.InvalidRevenueContract.selector);
        spigot.addSpigot(address(spigot), settings);
    }

    //  Updating
    function test_updateOwnerSplit_AsOwner() public {
        spigot.updateOwnerSplit(revenueContract, 0);
    }

    function test_updateOwnerSplit_0To100(uint8 split) public {
        if (split > 100) return;
        assertTrue(spigot.updateOwnerSplit(revenueContract, split));
        (uint8 split_, , ) = spigot.getSetting(revenueContract);
        assertEq(split, split_);
    }

    function test_updateOwnerSplit_AsNonOwner() public {
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        hoax(address(40));
        spigot.updateOwnerSplit(revenueContract, 0);
    }

    function test_updateOwnerSplit_Over100(uint8 split) public {
        if (split <= 100) return;
        vm.expectRevert(ISpigot.BadSetting.selector);
        spigot.updateOwnerSplit(revenueContract, split);
    }

    // Unclaimed Revenue no longer affectbs Spigot behaviour. Keep for docs
    function test_updateOwnerSplit_UnclaimedRevenue() public {
        // send revenue and dont claim
        // token.mint(address(spigot), type(uint).max);
        // // vm.expectRevert(ISpigot.UnclaimedRevenue.selector);
        // spigot.updateOwnerSplit(revenueContract, 0);     // reverts because excess tokens
    }

    // Operate()

    function test_operate_NonWhitelistedFunction() public {
        vm.prank(owner);
        assertTrue(spigot.updateWhitelistedFunction(opsFunc, false));

        vm.expectRevert(ISpigot.OperatorFnNotWhitelisted.selector);
        vm.prank(operator);
        spigot.operate(revenueContract, abi.encodeWithSelector(opsFunc));
    }

    function test_operate_OperatorCanOperate() public {
        vm.prank(owner);
        assertTrue(spigot.updateWhitelistedFunction(opsFunc, true));
        vm.prank(operator);
        assertTrue(
            spigot.operate(revenueContract, abi.encodeWithSelector(opsFunc))
        );
    }

    // should fail because the fn has not been whitelisted
    function test_operate_ClaimRevenueBadFunction() public {
        _initSpigot(
            address(token),
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        // we need to whitelist the transfer function in order to test the
        // correct error condition
        spigot.updateWhitelistedFunction(claimPullPaymentFunc, true);

        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        // vm.expectRevert(ISpigot.OperatorFnNotWhitelisted.selector);
        vm.expectRevert(ISpigot.OperatorFnNotValid.selector);
        vm.prank(operator);
        spigot.operate(revenueContract, claimData);
    }

    // should test trying to call operate on an existing transfer owner function
    function test_operate_TransferOwnerBadFunction() public {
        _initSpigot(
            address(token),
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        // we need to whitelist the transfer function in order to test the
        // correct error condition
        spigot.updateWhitelistedFunction(transferOwnerFunc, true);

        bytes memory transferData = abi.encodeWithSelector(
            transferOwnerFunc,
            address(operator)
        );
        vm.expectRevert(ISpigot.OperatorFnNotValid.selector);
        vm.prank(operator);
        spigot.operate(revenueContract, transferData);
    }

    function test_operate_callFails() public {
        _initSpigot(
            address(token),
            100,
            claimPullPaymentFunc,
            transferOwnerFunc,
            whitelist
        );

        spigot.updateWhitelistedFunction(
            SimpleRevenueContract.doAnOperationsThingWithArgs.selector,
            true
        );

        bytes memory operationsThingData = abi.encodeWithSelector(
            SimpleRevenueContract.doAnOperationsThingWithArgs.selector,
            5
        );

        vm.expectRevert(ISpigot.OperatorFnCallFailed.selector);
        vm.prank(operator);
        spigot.operate(revenueContract, operationsThingData);
    }

    function test_operate_AsNonOperator() public {
        hoax(address(0xdebf));
        bytes memory claimData = abi.encodeWithSelector(claimPullPaymentFunc);
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.operate(revenueContract, claimData);
    }

    function test_operate_NonWhitelistFunc() public {
        vm.expectRevert(ISpigot.OperatorFnNotWhitelisted.selector);
        vm.prank(operator);
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
        (, , bytes4 transferOwnerFunc_) = spigot.getSetting(revenueContract);
        assertEq(bytes4(transferOwnerFunc), transferOwnerFunc_);

        spigot.removeSpigot(revenueContract);

        (, , bytes4 transferOwnerFunc__) = spigot.getSetting(revenueContract);
        assertEq(bytes4(0), transferOwnerFunc__);
    }

    function test_removeSpigot_AsOperator() public {
        spigot.updateOwner(address(0xdebf)); // random owner

        assertEq(spigot.owner(), address(0xdebf));
        assertEq(spigot.operator(), operator);

        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.removeSpigot(revenueContract);
    }

    function test_removeSpigot_AsNonOwner() public {
        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.removeSpigot(revenueContract);
    }

    // Unclaimed Revenue no longer affectbs Spigot behaviour. Keep for docs
    function test_removeSpigot_UnclaimedRevenue() public {
        // // send revenue and dont claim
        // token.mint(address(spigot), type(uint).max);
        // vm.expectRevert(ISpigot.UnclaimedRevenue.selector);
        // spigot.claimEscrow(address(token));       // reverts because excess tokens
    }

    // Access Control Changes
    function test_updateOwner_AsOwner() public {
        spigot.updateOwner(address(0xdebf));
        assertEq(spigot.owner(), address(0xdebf));
    }

    function test_updateOperator_AsOperator() public {
        vm.prank(operator);
        spigot.updateOperator(address(0xdebf));
        assertEq(spigot.operator(), address(0xdebf));
    }

    function test_updateOperator_AsOwner() public {
        vm.prank(owner);
        spigot.updateOperator(address(20));
    }
    
    function test_updateOwner_AsNonOwner() public {
        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.updateOwner(owner);
    }

    function test_updateOwner_AsOperator() public {
        hoax(operator);
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.updateOwner(owner);
    }

    function test_updateOwner_NullAddress() public {
        vm.expectRevert();
        spigot.updateOwner(address(0));
    }

    function test_updateOperator_AsNonOperator() public {
        hoax(address(0xdebf));
        vm.expectRevert(ISpigot.CallerAccessDenied.selector);
        spigot.updateOperator(operator);
    }

    function test_cannot_add_spigot_with_spigot_as_revenue_contract() public {
        revenueContract = address(new SimpleRevenueContract(owner, address(new RevenueToken())));

        settings = ISpigot.Setting(10, bytes4(""), bytes4("1234"));

        spigot = new Spigot(owner, operator);

        vm.expectRevert(SpigotLib.InvalidRevenueContract.selector);
        spigot.addSpigot(address(spigot), settings);
    }

    function test_cannot_add_spigot_with_same_revenue_contract() public {
        revenueContract = address(new SimpleRevenueContract(owner, address(new RevenueToken())));

        settings = ISpigot.Setting(10, bytes4(""), bytes4("1234"));

        spigot = new Spigot(owner, operator);

        spigot.addSpigot(address(revenueContract), settings);

        ISpigot.Setting memory altSettings = ISpigot.Setting(50, bytes4(""), bytes4("1234"));
        
        vm.expectRevert(SpigotLib.SpigotSettingsExist.selector);
         spigot.addSpigot(address(revenueContract), altSettings);
    }

}
