pragma solidity 0.8.16;

import "forge-std/Test.sol";
import { RevenueShareAgreement } from "../modules/credit/RevenueShareAgreement.sol";
import { RSAFactory } from "../modules/factories/RSAFactory.sol";
import {Spigot} from "../modules/spigot/Spigot.sol";

import {RevenueToken} from "../mock/RevenueToken.sol";
import {SimpleRevenueContract} from "../mock/SimpleRevenueContract.sol";
import {Denominations} from "chainlink/Denominations.sol";
import {GPv2Order} from "../utils/GPv2Order.sol";

import {ISpigot} from "../interfaces/ISpigot.sol";
import {IRevenueShareAgreement} from "../interfaces/IRevenueShareAgreement.sol";

contract RevenueShareAgreementTest is Test, IRevenueShareAgreement {
    using GPv2Order for GPv2Order.Data;

    // spigot contracts/configurations to test against
    RevenueToken private revenueToken;
    RevenueToken private creditToken;
    address private revenueContract;
    Spigot private spigot;
    ISpigot.Setting private settings;
    uint8 private lenderRevenueSplit = 47;

    // Named vars for common inputs
    uint256 constant MAX_REVENUE = type(uint256).max / 100;
    // function signatures for mock revenue contract to pass as params to spigot
    bytes4 constant transferOwnerFunc =
        SimpleRevenueContract.transferOwnership.selector;
    bytes4 constant claimPushPaymentFunc = bytes4(0);
    bytes4 internal constant ERC_1271_MAGIC_VALUE =  0x1626ba7e;
    bytes4 internal constant ERC_1271_NON_MAGIC_VALUE = 0xffffffff;

    // RSA + Spigot stakeholder
    RSAFactory factory;
    RevenueShareAgreement private rsa;
    address private operator;
    address private borrower;
    address private lender;
    address private rando; // random address for ACL testing
    uint256 private initialPrincipal = 10_000 * 1e18;
    uint256 private totalOwed = 13_000 * 1e18;
  

    function setUp() public {
        operator = vm.addr(2);
        borrower = vm.addr(3);
        lender = vm.addr(4);
        rando = vm.addr(69);
        factory = new RSAFactory();
        
        revenueToken = new RevenueToken();
        creditToken = new RevenueToken();

        _initSpigot(
            address(revenueToken),
            lenderRevenueSplit,
            claimPushPaymentFunc,
            transferOwnerFunc
        );

        rsa = _initRSA(
            address(creditToken),
            initialPrincipal,
            totalOwed,
            lenderRevenueSplit
        );

        // Borrower must transfer their Spigot to the RSA to initiate deal
        // TODO move to helper function and add tests if we don't own spigot? 
        hoax(borrower);
        spigot.updateOwner(address(rsa));

        // TODO find some good revenue contracts to mock and deploy
    }

    /*********************
    **********************
    
    Factory/Proxy & Initialization Tests

    Unit Tests
    
    **********************
    *********************/

    function test_initialize_setsValuesProperly() public {
        // set in _initRSA
        assertEq("RSA Revenue Stream Token", rsa.name());
        assertEq("rsaCLAIM", rsa.symbol());
        // stakeholder addresses
        assertEq(borrower, rsa.borrower());
        assertEq(address(spigot), address(rsa.spigot()));

        // deal terms
        assertEq(totalOwed, rsa.totalOwed());
        assertEq(initialPrincipal, rsa.initialPrincipal());
        assertEq(lenderRevenueSplit, rsa.lenderRevenueSplit());
        assertEq(address(creditToken), address(rsa.creditToken()));
    }

    function test_initialize_revenueSplit0To100(uint8 _lenderRevenueSplit) public {
        if(_lenderRevenueSplit > 100) {
            vm.expectRevert(IRevenueShareAgreement.InvalidRevenueSplit.selector);
        }
        _initRSA(
            address(creditToken),
            initialPrincipal,
            totalOwed,
            _lenderRevenueSplit
        );
    }

    function test_initialize_mustOweMoreThanPrincipal(uint256 _principal, uint256 _totalDebt) public {
        if(_principal > _totalDebt) {
            vm.expectRevert(IRevenueShareAgreement.InvalidPaymentSetting.selector);
        }
        _initRSA(
            address(creditToken),
            _principal,
            _totalDebt,
            lenderRevenueSplit
        );
    }

    function test_initialize_mustBorrowNonNullAddress() public {
        vm.expectRevert(IRevenueShareAgreement.InvalidBorrowerAddress.selector);
        factory.createRSA(
            address(spigot),
            address(0), // here
            address(creditToken),
            lenderRevenueSplit,
            initialPrincipal,
            totalOwed,
            "RSA Revenue Stream Token",
            "rsaCLAIM"
        );
    }

    function test_initialize_mustSpigotNonNullAddress() public {
        vm.expectRevert(IRevenueShareAgreement.InvalidSpigotAddress.selector);
        factory.createRSA(
            address(0),  // here
            borrower,
            address(creditToken),
            lenderRevenueSplit,
            initialPrincipal,
            totalOwed,
            "RSA Revenue Stream Token",
            "rsaCLAIM"
        );
    }

    function test_initialize_cantInitializeTwice() public {
        vm.prank(borrower);
        vm.expectRevert(IRevenueShareAgreement.AlreadyInitialized.selector);
        rsa.initialize(
            address(spigot),
            borrower,
            address(creditToken),
            lenderRevenueSplit,
            initialPrincipal,
            totalOwed,
            "RSA Revenue Stream Token",
            "rsaCLAIM"
        );

        vm.prank(lender);
        vm.expectRevert(IRevenueShareAgreement.AlreadyInitialized.selector);
        rsa.initialize(
            address(spigot),
            borrower,
            address(creditToken),
            lenderRevenueSplit,
            initialPrincipal,
            totalOwed,
            "RSA Revenue Stream Token",
            "rsaCLAIM"
        );

        vm.prank(rando);
        vm.expectRevert(IRevenueShareAgreement.AlreadyInitialized.selector);
        rsa.initialize(
            address(spigot),
            borrower,
            address(creditToken),
            lenderRevenueSplit,
            initialPrincipal,
            totalOwed,
            "RSA Revenue Stream Token",
            "rsaCLAIM"
        );
    }

    // any tets for Proxy that we need to check e.g. same byte code for all deployed contracts?]


    /*********************
    **********************
    
    RSA deposit() and redem()

    Unit Tests
    
    **********************
    *********************/

    /// @notice manually recreate _depositRSA helper to test each step
    function test_deposit_lenderMustSendInitialPrincipal() public {
        uint256 lenderBalance0 = creditToken.balanceOf(lender);
        uint256 borrowerBalance0 = creditToken.balanceOf(borrower);
        uint256 rsaBalance0 = creditToken.balanceOf(address(rsa));
        deal(address(creditToken), lender, rsa.initialPrincipal());
        uint256 lenderBalance1 = creditToken.balanceOf(lender);
        // proper amount is minted to lender. assert lenderBalance befiore deposit
        assertEq(lenderBalance1, lenderBalance0 + rsa.initialPrincipal());
        
        vm.startPrank(lender);
        creditToken.approve(address(rsa), type(uint256).max);
        rsa.deposit();

        uint256 lenderBalance2 = creditToken.balanceOf(lender);
        uint256 borrowerBalance1 = creditToken.balanceOf(borrower);
        uint256 rsaBalance1 = creditToken.balanceOf(address(rsa));
        // ensure proper amount moved from lender
        assertEq(lenderBalance2, lenderBalance1 - rsa.initialPrincipal(), 'bad post deposit() lender balance');
        // ensure proper amount moved to borrower
        assertEq(borrowerBalance1, borrowerBalance0 + rsa.initialPrincipal(), 'bad post deposit() borrower balance');
        // RSA should receive/hold no balance
        assertEq(rsaBalance1, rsaBalance0, 'bad post deposit() rsa balance');
    }

    function test_deposit_increasesTotalSupplyByTotalClaims() public {
        uint256 rsaSupply0 = rsa.totalSupply();
        assertEq(rsaSupply0, 0);
        
        _depositRSA(lender, rsa);

        uint256 rsaSupply1 = rsa.totalSupply();
        assertEq(rsaSupply1, totalOwed);
    }


    function test_deposit_increasesLenderClaimBalanceByTotalOwed() public {
        uint256 lenderBalance0 = rsa.balanceOf(lender);
        assertEq(lenderBalance0, 0);
        
        _depositRSA(lender, rsa);

        uint256 lenderBalance1 = rsa.balanceOf(lender);
        assertEq(lenderBalance1, totalOwed);
        // lender should have entire supply of RSA
        assertEq(lenderBalance1, rsa.totalSupply());
    }


    function test_deposit_onlyCallableOnce() public {
        _depositRSA(lender, rsa);
        
        vm.startPrank(lender);
        vm.expectRevert(IRevenueShareAgreement.DepositsFull.selector);
        // reverts before ERC20 transfer so no approval needed
        rsa.deposit();
        vm.stopPrank();

        vm.startPrank(rando);
        vm.expectRevert(IRevenueShareAgreement.DepositsFull.selector);
        // reverts before ERC20 transfer so no approval needed
        rsa.deposit();
        vm.stopPrank();

        vm.startPrank(lender);
        vm.expectRevert(IRevenueShareAgreement.DepositsFull.selector);
        // reverts before ERC20 transfer so no approval needed
        rsa.deposit();
        vm.stopPrank();
    }

    function test_deposit_borrowerGetsInitialPrincipalOnDeposit() public {
        uint256 balance1 = creditToken.balanceOf(borrower);
        _depositRSA(lender, rsa);
        uint256 balance2 = creditToken.balanceOf(borrower);
        assertEq(balance2 - balance1, rsa.initialPrincipal());
    }

    function test_redeem_reducesClaimsTotalSupply(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, totalOwed);
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(lender, rsa);
        assertEq(rsa.totalSupply(), totalOwed);
        // checkpoint lender underlying balance after depositing to assert redeemed amount
        uint256 lenderBalance0 = creditToken.balanceOf(lender);

        (uint256 claimableRev, ) = _generateRevenue(revenueContract, creditToken, redeemed);
        rsa.claimRev(address(creditToken));

        vm.prank(lender);
        rsa.redeem(lender, lender, claimableRev);
        vm.stopPrank();

        assertEq(rsa.totalSupply(), totalOwed - claimableRev);
        uint256 lenderBalance1 = creditToken.balanceOf(lender);
        assertEq(lenderBalance1, lenderBalance0 + claimableRev);
    }

    function test_redeem_reducesClaimsAvailable(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, totalOwed);
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(lender, rsa);
        assertEq(rsa.totalSupply(), totalOwed);
        // checkpoint lender underlying balance after depositing to assert redeemed amount
        uint256 claimable0 = rsa.claimableAmount();
        assertEq(claimable0, 0); // no rev claimed to rsa yet

        (uint256 claimableRev, ) = _generateRevenue(revenueContract, creditToken, redeemed);
        rsa.claimRev(address(creditToken));

        uint256 claimable1 = rsa.claimableAmount();
        assertEq(claimable1, claimableRev); // all rev generated is claimable

        vm.prank(lender);
        rsa.redeem(lender, lender, claimableRev);
        vm.stopPrank();

        uint256 claimable2 = rsa.claimableAmount();
        assertEq(claimable2, claimable1 - claimableRev);
    }


    function test_redeem_reducesClaimsAsLender(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, totalOwed);
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(lender, rsa);
        assertEq(rsa.totalSupply(), totalOwed);
        // checkpoint lender underlying balance after depositing to assert redeemed amount
        uint256 lenderClaims0 = rsa.balanceOf(lender);
        assertEq(lenderClaims0, totalOwed);

        (uint256 claimableRev, ) = _generateRevenue(revenueContract, creditToken, redeemed);
        rsa.claimRev(address(creditToken));

        vm.prank(lender);
        rsa.redeem(lender, lender, claimableRev);
        vm.stopPrank();

        uint256 lenderClaims1 = rsa.balanceOf(lender);
        assertEq(lenderClaims1, lenderClaims0 - claimableRev);
    }

    function test_redeem_reducesClaimsAsNonLender(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, totalOwed);
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(lender, rsa);
        assertEq(rsa.totalSupply(), totalOwed);
        // checkpoint lender underlying balance after depositing to assert redeemed amount
        uint256 lenderClaims0 = rsa.balanceOf(lender);
        assertEq(lenderClaims0, totalOwed);

        (uint256 claimableRev, ) = _generateRevenue(revenueContract, creditToken, redeemed);
        rsa.claimRev(address(creditToken));

        // transfer RSA claims to someone else and let them redeem
        vm.prank(lender);
        rsa.transfer(rando, claimableRev);
        vm.stopPrank();
        
        uint256 lenderClaims1 = rsa.balanceOf(lender);
        assertEq(lenderClaims1, lenderClaims0 - claimableRev);
        
        uint256 randoClaims0 = rsa.balanceOf(rando);
        uint256 randoBalance0 = creditToken.balanceOf(rando);
        assertEq(randoClaims0, claimableRev);

        vm.prank(rando);
        rsa.redeem(rando, rando, claimableRev);
        vm.stopPrank();
        
        uint256 randoClaims1 = rsa.balanceOf(rando);
        assertEq(randoClaims1, randoClaims0 - claimableRev);
        uint256 randoBalance1 = creditToken.balanceOf(rando);
        assertEq(randoBalance1, randoBalance0 + claimableRev);
    }

    function test_redeem_mustApproveReferrer(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, totalOwed);
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(lender, rsa);
        assertEq(rsa.totalSupply(), totalOwed);
        // checkpoint lender underlying balance after depositing to assert redeemed amount
        uint256 lenderClaims0 = rsa.balanceOf(lender);
        assertEq(lenderClaims0, totalOwed);

        (uint256 claimableRev, ) = _generateRevenue(revenueContract, creditToken, redeemed);
        rsa.claimRev(address(creditToken));


        uint256 randoAllowance0 = rsa.allowance(lender, rando);
        assertEq(randoAllowance0, 0);

        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(
            IRevenueShareAgreement.InsufficientAllowance.selector,
            lender, rando, claimableRev, 0
        ));
        rsa.redeem(lender, lender, claimableRev);
        vm.stopPrank();

        
        // transfer RSA claims to someone else and let them redeem
        vm.prank(lender);
        rsa.approve(rando, claimableRev);
        vm.stopPrank();

        uint256 randoAllowance1 = rsa.allowance(lender, rando);
        assertEq(randoAllowance1, randoAllowance0 + claimableRev);

        vm.prank(rando);
        rsa.redeem(lender, lender, claimableRev);
        vm.stopPrank();

        uint256 randoAllowance2 = rsa.allowance(lender, rando);
        assertEq(randoAllowance2, randoAllowance1 - claimableRev);
    }

    function test_redeem_reducesApprovalAsReferrer(uint256 _redeemed) public {
        uint256 redeemed = bound(_redeemed, 100, totalOwed);
        assertEq(rsa.totalSupply(), 0);

        _depositRSA(lender, rsa);
        assertEq(rsa.totalSupply(), totalOwed);
        // checkpoint lender underlying balance after depositing to assert redeemed amount
        uint256 lenderClaims0 = rsa.balanceOf(lender);
        assertEq(lenderClaims0, totalOwed);

        (uint256 claimableRev, ) = _generateRevenue(revenueContract, creditToken, redeemed);
        rsa.claimRev(address(creditToken));

        // transfer RSA claims to someone else and let them redeem
        vm.prank(lender);
        rsa.approve(rando, claimableRev);
        vm.stopPrank();

        uint256 randoAllowance0 = rsa.allowance(lender, rando);

        vm.prank(rando);
        rsa.redeem(lender, lender, claimableRev);
        vm.stopPrank();

        uint256 randoAllowance1 = rsa.allowance(lender, rando);
        assertEq(randoAllowance1, randoAllowance0 - claimableRev);
    }

    /*********************
    **********************
    
    RSA Spigot & Revenue Stream Management

    Integration Tests
    
    **********************
    *********************/
    // (trying not to do unit tests for Spigot and test in integration and assume basic stuff is handled in Spigot unit tests)

    // claimRev updates our token balance by amount spigot claimOwnerTokens event says we claimed
    // repay updates claimable amounts
    // repay emits Repay event
    // repay can only increase claimable amount
    // repay does not transfer tokens out of RSA
    // repay increases claimbale by `token.balance - self.claimable`
    // repay caps total claimable to total debt if newPayment > total debt
    // addSpigot only borrower callable
    // addSpigot invariant only og initialized rev split
    // setRevenueSplit invariant can only set split to initialized rev split
    // setWhitelist only lender callable




    /*********************
    **********************
    
    Borrower Reclaimation

    Unit Tests
    
    **********************
    *********************/
    // only borrower can sweep
    // only borrower can releaseSpigot
    // can sweep if no lender/deposit yet
    // can releaseSpigot if no lender/deposit yet
    // can sweep if lender and no debt
    // can releaseSpigot if lender and no debt
    // releaseSpigot updates spigot owner to _to (don't need to block rsa address bc can just call releaseSpigot again)
    // sweep updates _token balance of rsa
    // sweep updates _token balance of _to



    /*********************
    **********************
    
    CowSwap Market Order Creation

    Integration Tests
    
    **********************
    *********************/

    function test_initiateOrder_returnsOrderHash() public {
        _depositRSA(lender, rsa);
        vm.startPrank(lender);
        bytes32 orderHash = rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        assertTrue(orderHash != bytes32(0));
        vm.stopPrank();
    }

    /// @dev invariant
    function test_initiateOrder_mustSellOver1Token() public {
        _depositRSA(lender, rsa);
        vm.startPrank(lender);
        vm.expectRevert("Invalid trade amount");
        rsa.initiateOrder(address(revenueToken), 0, 0, uint32(block.timestamp + 100 days));
        vm.stopPrank();
    }

    /// @dev invariant
    function test_initiateOrder_cantTradeIfNoDebt() public {
        // havent deposited so no debt
        vm.startPrank(borrower);
        vm.expectRevert("Trade not required");
        rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        vm.stopPrank();

        vm.startPrank(lender);
        vm.expectRevert("Trade not required");
        rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        vm.stopPrank();

        vm.startPrank(rando);
        vm.expectRevert("Trade not required");
        rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        vm.stopPrank();
    }

    /// @dev invariant
    function test_initiateOrder_cantSellCreditToken() public {
        _depositRSA(lender, rsa);
        vm.startPrank(lender);
        vm.expectRevert("Cant sell token being bought");
        rsa.initiateOrder(address(creditToken), 1, 0, uint32(block.timestamp + 100 days));
        vm.stopPrank();
    }

    function test_initiateOrder_lenderOrBorrowerCanSubmit() public {
        _depositRSA(lender, rsa);
        vm.startPrank(lender);
        rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        vm.stopPrank();
        vm.startPrank(borrower);
        rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        vm.stopPrank();
        
        vm.startPrank(rando);
        vm.expectRevert("Caller must be stakeholder");
        rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        vm.stopPrank();
    }

    function test_initiateOrder_storesOrderData() public {
        _depositRSA(lender, rsa);
        bytes32 orderId = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days)).hash(rsa.DOMAIN_SEPARATOR());
        assertEq(rsa.orders(orderId), 0);

        vm.startPrank(lender);
        rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        assertEq(rsa.orders(orderId), 1);
        vm.stopPrank();
    }

    function _initOrder(address _sellToken, uint256 _sellAmount, uint32 _deadline) internal returns(bytes32) {
        _depositRSA(lender, rsa);
        vm.startPrank(lender);
        return rsa.initiateOrder(address(_sellToken), _sellAmount, 0, _deadline);
    }

    /*********************
    **********************
    
    EIP-2981 Order Verification
    
    **********************
    *********************/

    function test_verifySignature_mustInitiateOrderFirst() public {
        GPv2Order.Data memory order = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        bytes32 expectedOrderId = order.hash(rsa.DOMAIN_SEPARATOR());
        assertEq(rsa.orders(expectedOrderId), 0);

        vm.expectRevert(IRevenueShareAgreement.InvalidTradeId.selector);
        rsa.isValidSignature(expectedOrderId, abi.encode(order)); // orderId is the signed orderdata

        bytes32 orderId = _initOrder(address(revenueToken), 1, uint32(block.timestamp + 100 days));
        // signature should be valid now that we initiated order
        bytes4 value = rsa.isValidSignature(expectedOrderId, abi.encode(order)); // orderId is the signed orderdata
        // assert all state changes since isValidSignature might return NON_MAGIC_VALUE
        assertEq(value, ERC_1271_MAGIC_VALUE);
        assertEq(expectedOrderId, orderId);
        assertEq(rsa.orders(expectedOrderId), 1);
    }

    /// @dev invariant
    function test_verifySignature_mustUseERC20Balance() public {
        revert();
    }

    /// @dev invariant
    function test_verifySignature_mustBuyCreditToken() public {
        revert();
    }

    /// @dev invariant
    function test_verifySignature_mustBeSellOrder() public {
        revert();
    }

    /// @dev invariant
    function test_verifySignature_mustSignOrderFromCowContract() public {
        revert();
    }

    function test_verifySignature_returnsMagicValue() public {
        GPv2Order.Data memory order = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        bytes32 orderId = _initOrder(address(revenueToken), 1, uint32(block.timestamp + 100 days));
        // signature should be valid now that we initiated order
        bytes4 value = rsa.isValidSignature(orderId, abi.encode(order)); // orderId is the signed orderdata
        assertEq(value, ERC_1271_MAGIC_VALUE);
    }


    /*********************
    **********************
    
    Event Emissions
    
    Unit Tests
    
    **********************
    *********************/

    function test_deposit_emitsDepositEvent() public {
        vm.expectEmit(true, true, false, true, address(rsa));
        emit Deposit(lender);
        _depositRSA(lender, rsa);
    }

    function test_redeem_emitsRedeemEvent() public {
        _depositRSA(lender, rsa);

        _generateRevenue(revenueContract, creditToken, MAX_REVENUE);
        rsa.claimRev(address(creditToken));

        vm.prank(lender);
        vm.expectEmit(true, true, false, true, address(rsa));
        emit Redeem(lender, lender, lender, 1);
        rsa.redeem(lender, lender, 1);
        vm.stopPrank();
    }

    function test_initiateOrder_emitsTradeInitiatedEvent() public {
        _depositRSA(lender, rsa);
        bytes32 orderId = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days)).hash(rsa.DOMAIN_SEPARATOR());
        assertEq(rsa.orders(orderId), 0);

        vm.startPrank(lender);
        vm.expectEmit(true, true, false, true, address(rsa));
        emit TradeInitiated(orderId, 1, 0, uint32(block.timestamp + 100 days));
        rsa.initiateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        assertEq(rsa.orders(orderId), 1);
        vm.stopPrank();
    }


    /*********************
    **********************
    
    Testing Helpers & Automations
    
    **********************
    *********************/

    /**
     * @dev Creates a new Revenue Share Agreement mints token to lender and approves to RSA
    * @param _token address of token being lent
    * @param _initialPrincipal amount of tokens to lend
    * @param _totalOwed total amount of tokens owed to lender through RSA
    * @param _revSplit % of revenue given to lender
     */
    function _initRSA(
        address _token,
        uint256 _initialPrincipal,
        uint256 _totalOwed,
        uint8 _revSplit
    ) internal returns(RevenueShareAgreement newRSA) {
        address _newRSA = factory.createRSA(
            address(spigot),
            borrower,
            _token,
            _revSplit,
            _initialPrincipal,
            _totalOwed,
            "RSA Revenue Stream Token",
            "rsaCLAIM"
        );
        return RevenueShareAgreement(_newRSA);
    }

      function _depositRSA(
        address _lender,
        RevenueShareAgreement _rsa
    ) internal {
        creditToken.mint(_lender, rsa.initialPrincipal());
        // deal(address(creditToken), _lender, rsa.initialPrincipal());
        vm.startPrank(_lender);
        creditToken.approve(address(_rsa), type(uint256).max);
        _rsa.deposit();
        vm.stopPrank();
    }

    /**
     * @dev sends tokens through spigot and makes claimable for owner and operator
     */
    function _generateRevenue(
        address _revenueContract,
        RevenueToken _token,
        uint256 _amount
    ) internal returns(uint256 ownerTokens, uint256 operatorTokens) {

        (uint8 split, bytes4 claimFunc, ) = spigot.getSetting(_revenueContract);
        _token.mint(address(spigot), _amount);
        /// @dev assumes claim func is push payment bc thats easiest to test
        /// need to pass in claim data as param to support claim payments
        bytes memory claimData = abi.encodeWithSelector(claimFunc);
        spigot.claimRevenue(_revenueContract, address(_token), claimData);
        
        return _assertSpigotSplits(address(_token), _amount);
    }

    /**
     * @dev Helper function to initialize new Spigots with different params to test functionality
     */
    function _initSpigot(
        address _token,
        uint8 _split,
        bytes4 _claimFunc,
        bytes4 _newOwnerFunc
    ) internal returns(address) {
        spigot = new Spigot(borrower, operator);

        // deploy new revenue contract with settings
        revenueContract = _addRevenueContract(spigot, borrower, _token, _split, _claimFunc, _newOwnerFunc);

        return address(spigot);
    }


    /**
     * @dev Helper function to initialize new Spigots with different params to test functionality
     */
    function _addRevenueContract(
        Spigot _spigot,
        address _owner,
        address _token,
        uint8 _split,
        bytes4 _claimFunc,
        bytes4 _newOwnerFunc
    ) internal returns(address) {
        // deploy new revenue contract with settings
        address newRevenueContract = address(new SimpleRevenueContract(_owner, _token));

        settings = ISpigot.Setting(_split, _claimFunc, _newOwnerFunc);

        vm.startPrank(_owner);
        // add spigot for revenue contract
        require(
            _spigot.addSpigot(newRevenueContract, settings),
            "Failed to add spigot"
        );

        // give spigot ownership to claim revenue
        newRevenueContract.call(
            abi.encodeWithSelector(_newOwnerFunc, address(spigot))
        );

        vm.stopPrank();

        return newRevenueContract;
    }
    // Claiming functions


    // Claim Revenue - payment split and escrow accounting

    /**
     * @dev helper func to get max revenue payment claimable in Spigot.
     *      Prevents uint overflow on owner split calculations
    */
    function _getMaxRevenue(uint256 totalRevenue) internal pure returns(uint256, uint256) {
        if(totalRevenue > MAX_REVENUE) return(MAX_REVENUE, totalRevenue - MAX_REVENUE);
        return (totalRevenue, 0);
    }

    /**
     * @dev helper func to check revenue payment streams to `ownerTokens` and `operatorTokens` happened and Spigot is accounting properly.
    */
    function _assertSpigotSplits(address _token, uint256 totalRevenue)
        internal
        returns(uint256 ownerTokens, uint256 operatorTokens)
    {
        (uint256 maxRevenue, uint256 overflow) = _getMaxRevenue(totalRevenue);
        ownerTokens = maxRevenue * settings.ownerSplit / 100;
        operatorTokens = maxRevenue - ownerTokens;
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
            operatorTokens,
            'Invalid treasury payment amount for spigot revenue'
        );
    }
}
