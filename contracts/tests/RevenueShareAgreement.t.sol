pragma solidity 0.8.16;

import "forge-std/Test.sol";
import { RevenueShareAgreement } from "../modules/credit/RevenueShareAgreement.sol";
import { RSAFactory } from "../modules/factories/RSAFactory.sol";
import {Spigot} from "../modules/spigot/Spigot.sol";

import {RevenueToken} from "../mock/RevenueToken.sol";
import {SimpleRevenueContract} from "../mock/SimpleRevenueContract.sol";
import {Denominations} from "chainlink/Denominations.sol";
import {GPv2Order} from "../utils/GPv2Order.sol";
import {SpigotLib} from "../utils/SpigotLib.sol";

import {ISpigot} from "../interfaces/ISpigot.sol";
import {IRevenueShareAgreement} from "../interfaces/IRevenueShareAgreement.sol";
import {ISpigot} from "../interfaces/ISpigot.sol";


// TODO: cant do invariants bc setup funcs like _deposit and _initOrder affect state not being tested
// Setup helper test contract with deposit() and redeem() initiaiteOrder() defined with setup logic before those funcs get called 

contract RevenueShareAgreementTest is Test, IRevenueShareAgreement, ISpigot {
    using GPv2Order for GPv2Order.Data;

    // spigot contracts/configurations to test against
    RevenueToken private revenueToken;
    RevenueToken private creditToken;
    address private revenueContract;
    Spigot private spigot;
    ISpigot.Setting private settings;
    uint8 private lenderRevenueSplit = 47;

    // Named vars for common inputs
    uint256 constant MAX_UINT = type(uint256).max;
    uint256 constant MAX_REVENUE = type(uint256).max / 100;
    // function signatures for mock revenue contract to pass as params to spigot
    bytes4 constant transferOwnerFunc =
        SimpleRevenueContract.transferOwnership.selector;
    bytes4 constant claimPushPaymentFunc = bytes4(0);
    bytes4 internal constant ERC_1271_MAGIC_VALUE =  0x1626ba7e;
    bytes4 internal constant ERC_1271_NON_MAGIC_VALUE = 0xffffffff;
    /// @dev The settlement contract's EIP-712 domain separator. Milkman uses this to verify that a provided UID matches provided order parameters.
    bytes32 internal constant COWSWAP_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

    // RSA + Spigot stakeholder
    RSAFactory factory;
    RevenueShareAgreement private rsa;
    address public operator;
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

    function test_initialize_canSetPrincipalTo0() public {
        _initRSA(
            address(creditToken),
            0,
            totalOwed,
            lenderRevenueSplit
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

    function test_deposit_mustSetLender() public {
        address lendy = rsa.lender();
        assertEq(lendy, address(0));
        
        _depositRSA(lender, rsa);

        address lendy2 = rsa.lender();
        assertEq(lendy2, lender);
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

    function test_redeem_mustRedeemLessThanClaimableRevenue(uint256 _revenue, uint256 _redeemed) public {
        uint256 revenue = bound(_revenue, 100, MAX_UINT);
        uint256 redeemed = bound(_redeemed, 100, totalOwed);

        _depositRSA(lender, rsa);
        (uint256 claimableRev, ) = _generateRevenue(revenueContract, creditToken, revenue);
        rsa.claimRev(address(creditToken));

        vm.prank(lender);
        if(redeemed > claimableRev) {
            vm.expectRevert(abi.encodeWithSelector(
                IRevenueShareAgreement.ExceedClaimableTokens.selector,
                claimableRev
            ));
        }
        rsa.redeem(lender, lender, redeemed);
        vm.stopPrank();
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
        vm.expectRevert();
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

    /**
    * @notice - allowing functionality bc could be used as a new crowdfunding method
    * with principal = 0, can bootstrap your own token as claims on future revenue instead of equity
    * so you deposit() yourself and get RSA tokens and sell those to investors for capital
    * probably at a deep discount e.g 1/5th of the value of the underlying revenue
    */
    function test_deposit_with0Principal() public {
        RevenueShareAgreement _rsa = RevenueShareAgreement(_initRSA(
            address(creditToken),
            0,
            totalOwed,
            lenderRevenueSplit
        ));
        uint256 balance1 = creditToken.balanceOf(borrower);
        _depositRSA(lender, _rsa);
        uint256 balance2 = creditToken.balanceOf(borrower);
        
        assertEq(balance1, 0); // had no tokens
        assertEq(balance2, balance1); // still have no tokens
        assertEq(_rsa.initialPrincipal(), balance1 - balance2); // supposed to give 0 tokens
        assertEq(_rsa.balanceOf(lender), totalOwed); // got all claims
    }

    /*********************
    **********************
    
    RSA Spigot & Revenue Stream Management

    Integration Tests
    
    **********************
    *********************/
    // (trying not to do unit tests for Spigot and test in integration and assume basic stuff is handled in Spigot unit tests)

    function test_claimRev_mustUpdateTokenBalances(uint256 _revenue) public {
        // ensure our revenue logic matches with Spigot event
        // manually generate revenue instead of _gerneateRevenue for granular checks

        uint256 revenue = bound(_revenue, 100, MAX_REVENUE);
        uint256 revenueForOwner = (revenue * lenderRevenueSplit) / 100;
        revenueToken.mint(address(spigot), revenue);
        bytes memory claimData = abi.encodeWithSelector(claimPushPaymentFunc);
        vm.expectEmit(true, true, true, true); // cant check calldata bc we send other tx after claimRevneue in _genereateRevenue
        emit ClaimRevenue(revenueContract, address(revenueToken), revenue, revenueForOwner);
        spigot.claimRevenue(revenueContract, address(revenueToken), claimData);
        (uint256 claimableRev, ) = _assertSpigotSplits(address(revenueToken), revenue, lenderRevenueSplit);

        uint256 rsaBalance0 = revenueToken.balanceOf(address(rsa));
        uint256 spigotBalance0 = revenueToken.balanceOf(address(spigot));

        emit log_named_uint("balances", rsaBalance0);
        emit log_named_uint("balances", spigotBalance0);

        assertEq(rsaBalance0, 0);
        assertEq(spigotBalance0, revenue);
        // ensure our revenue logic matches with Spigot storage data
        assertEq(spigot.getOwnerTokens(address(revenueToken)), claimableRev, "Spigot revenue doesnt match expected value");
        assertGe(revenueForOwner, claimableRev, "ClaimRev event and Spigot storage data do not match");
        
        rsa.claimRev(address(revenueToken));

        uint256 rsaBalance1 = revenueToken.balanceOf(address(rsa));
        uint256 spigotBalance1 = revenueToken.balanceOf(address(spigot));
        assertEq(rsaBalance1, claimableRev);
        assertEq(spigotBalance1, revenue - claimableRev);
        assertEq(spigot.getOwnerTokens(address(revenueToken)), 0);
    }

    /// @dev invariant
    function test_claimRev_repayParity(uint256 _revenue) public {
        // semantic naming to show feature parity between claimRev and repay
        // separate from actual repay functionality
        test_claimRev_mustRepayOnCreditTokenRevenue(_revenue);
    }

    function test_claimRev_mustRepayOnCreditTokenRevenue(uint256 _revenue) public {
        uint256 revenue = bound(_revenue, 100, totalOwed);
        (uint256 claimableRev, ) = _generateRevenue(revenueContract, creditToken, revenue);

        uint256 rsaBalance0 = creditToken.balanceOf(address(rsa));
        assertEq(rsaBalance0, 0);
        assertEq(rsa.claimableAmount(), 0);

        rsa.claimRev(address(creditToken));

        uint256 rsaBalance1 = creditToken.balanceOf(address(rsa));
        assertEq(rsaBalance1, claimableRev);
        assertEq(rsa.claimableAmount(), claimableRev);

        uint256 rsaRevenueBalance0 = revenueToken.balanceOf(address(rsa));
        assertEq(rsaRevenueBalance0, 0);

        (uint256 claimableRev1, ) = _generateRevenue(revenueContract, revenueToken, revenue);
        rsa.claimRev(address(revenueToken));
        // rsa has receieved revenue tokens
        uint256 rsaRevenueBalance1 = revenueToken.balanceOf(address(rsa));
        assertEq(rsaRevenueBalance1, claimableRev1);
        // non creditToken revenue should not be auto-repaid
        assertEq(rsa.claimableAmount(), claimableRev);
    }

    /**
    * @notice - can claim revenue anytime if RSA owns spigot and has claimable rev
                even if there is no debt
    */
    function test_claimRev_anyoneAnytime(uint256 _totalOwed, uint256 _revenue) public {
        uint256 totalDebt = bound(_totalOwed, initialPrincipal, MAX_REVENUE);
        uint256 revenue = bound(_revenue, 100, MAX_REVENUE);
        uint256 totalRevenue;
        address[3] memory claimers = [rando, borrower, lender];

        for(uint256 i; i < 3; i++) {
            // deploy new rsa to test for claimer to reset debt so we can repay again
            RevenueShareAgreement newRSA = _initRSA(
                address(creditToken),
                initialPrincipal,
                totalDebt,
                lenderRevenueSplit
            );

            // pay off last RSA so we can transfer Spigot on next loop
            creditToken.mint(address(rsa), rsa.totalOwed());
            rsa.repay();
            assertEq(rsa.totalOwed(), 0, "bad debt");
            hoax(borrower);
            rsa.releaseSpigot(address(newRSA));
            
            vm.startPrank(claimers[i]);
            // claim rev to RSA before even depositing to RSA
            (uint256 preDepositlaimableRev, ) = _generateRevenue(revenueContract, creditToken, revenue);
            uint256 preDepositClaimableBalance0 = creditToken.balanceOf(address(newRSA));
            assertEq(preDepositClaimableBalance0, totalRevenue, "pre deposit rev #1");
            uint256 revClaimed = newRSA.claimRev(address(creditToken));
            assertEq(preDepositlaimableRev, revClaimed, "claimable rev #1");
            totalRevenue += revClaimed;
            uint256 preDepositClaimableBalance1 = creditToken.balanceOf(address(newRSA));
            assertEq(preDepositClaimableBalance1, totalRevenue, "pre deposit rev #2");
            vm.stopPrank();
            
            // clear operator tokens so _assertSpigot in _generateRevenue passes on multiple invocations
            hoax(operator);
            spigot.claimOperatorTokens(address(creditToken));

            // ensure we can claim revenue after depositing too
            _depositRSA(lender, newRSA);

            vm.startPrank(claimers[i]);
            // claim rev to RSA after depositing to RSA
            (uint256 postDepositClaimableRev, ) = _generateRevenue(revenueContract, creditToken, revenue);
            uint256 postDepositClaimableBalance0 = creditToken.balanceOf(address(newRSA));
            assertEq(postDepositClaimableBalance0, totalRevenue, "post deposit rev #1");
            uint256 revClaimed2 = newRSA.claimRev(address(creditToken));
            assertEq(postDepositClaimableRev, revClaimed2, 'claimable rev #2');
            totalRevenue += revClaimed2;
            uint256 postDepositClaimableBalance1 = creditToken.balanceOf(address(newRSA));
            assertEq(postDepositClaimableBalance1, totalRevenue, "post deposit rev #2");
            vm.stopPrank();


            // update old rsa for transferring for next iteration
            rsa = newRSA;
            // clear out old revenue vars from last iteration
            totalRevenue = 0;
            // reset rev for new rsa
            // clear operator tokens so _assertSpigot in _generateRevenue passes on multiple invocations
            hoax(operator);
            spigot.claimOperatorTokens(address(creditToken));
        }
    }

    function test_repay_mustWorkBeforeLenderDeposits() public {
        // no deposit helper called here
        creditToken.mint(address(rsa), rsa.totalOwed());
        rsa.repay();
    }

    function test_repay_acceptsNonSpigotPayment() public {
        _depositRSA(lender, rsa);
        creditToken.mint(address(rsa), rsa.totalOwed());
        rsa.repay();
    }

    function test_repay_acceptsTradedRevenueRepayments(uint128 _revenue) public {
        uint256 revenue = bound(_revenue, 100, MAX_UINT);
        _depositRSA(lender, rsa);
        
        (uint256 revenueClaimed, ) = _generateRevenue(revenueContract, revenueToken, revenue);
        rsa.claimRev(address(revenueToken));
        
        // now have revenue but no claimableCredits credit tokens
        assertEq(revenueToken.balanceOf(address(rsa)), revenueClaimed, "bad pre trade rev token balance");
        assertEq(creditToken.balanceOf(address(rsa)), 0, "bad pre trade cred token balance");
        assertEq(rsa.claimableAmount(), 0);
        assertEq(rsa.totalOwed(), totalOwed);

        uint256 bought = _tradeRevenue(revenueToken, revenueClaimed, totalOwed);
        uint256 claimableCredits = bound(bought, 0, totalOwed);

        // debt hasnt been updated even though we traded revenue
        // should only update in repay() call
        assertEq(revenueToken.balanceOf(address(rsa)), 0, "bad prepay rev token RSA balance");
        assertEq(creditToken.balanceOf(address(rsa)), bought, "bad prepay credit token RSA balance");
        assertEq(rsa.claimableAmount(), 0);
        assertEq(rsa.totalOwed(), totalOwed);

        rsa.repay();
        
        assertEq(revenueToken.balanceOf(address(rsa)), 0, "bad final rev token RSA balance");
        assertEq(creditToken.balanceOf(address(rsa)), bought, "bad final credit token RSA balance");
        assertEq(rsa.claimableAmount(), claimableCredits);
        assertEq(rsa.totalOwed(), totalOwed - bought);
    }

    function test_repay_mustWorkAfterLenderDeposits() public {
        _depositRSA(lender, rsa);
        _generateRevenue(revenueContract, creditToken, MAX_REVENUE);
        rsa.claimRev(address(creditToken));
    }

    function test_repay_storesPaymentInRSA() public {
        // ensure we do not send token to lender either as a negative case
        _depositRSA(lender, rsa);

        _generateRevenue(revenueContract, creditToken, MAX_REVENUE);
        uint256 claimed = rsa.claimRev(address(creditToken));
        // RSA holds full revenue amount even if greater than owed for borrowerto sweep after lender claims
        assertEq(creditToken.balanceOf(address(rsa)), claimed);
        assertEq(creditToken.balanceOf(lender), 0);
        assertEq(creditToken.balanceOf(borrower), initialPrincipal);
    }

    function test_repay_doesNotTransferTokensToLender() public {
        // wrapper function for semantics
        test_repay_storesPaymentInRSA();
    }

    /// @dev invariant
    function test_repay_mustIncreaseClaimableAmount() public {
        // ensure we do not send token to lender either as a negative case
        assertEq(rsa.claimableAmount(), 0);
        _depositRSA(lender, rsa);

        _generateRevenue(revenueContract, creditToken, MAX_REVENUE);
        assertEq(rsa.claimableAmount(), 0);

        uint256 claimed = rsa.claimRev(address(creditToken));
        uint256 claimable = claimed > totalOwed ? totalOwed : claimed;
        assertEq(creditToken.balanceOf(address(rsa)), claimed);
        assertEq(rsa.claimableAmount(), claimable);
        assertGe(claimable, 0); // mustve increased something
    }

    /// @dev invariant
    function test_repay_increasesClaimableAmountByCurrentBalanceMinusExistingClaimable() public {
        _depositRSA(lender, rsa);
        _generateRevenue(revenueContract, creditToken, initialPrincipal);
        // clear operator tokens so _assertSpigot in _generateRevenue passes on multiple invocations
        hoax(operator);
        spigot.claimOperatorTokens(address(creditToken));

        assertEq(creditToken.balanceOf(address(rsa)), 0);
        assertEq(rsa.claimableAmount(), 0);

        uint256 claimed = rsa.claimRev(address(creditToken));
        uint256 claimable = claimed > totalOwed ? totalOwed : claimed;
        assertEq(creditToken.balanceOf(address(rsa)), claimed);
        assertGe(claimable, 0); //must actually claim for test to be valid
        assertEq(rsa.claimableAmount(), claimable); // updated claimable properly


        _generateRevenue(revenueContract, creditToken, initialPrincipal);
        // clear operator tokens so _assertSpigot in _generateRevenue passes on multiple invocations
        hoax(operator);
        spigot.claimOperatorTokens(address(creditToken));

        uint256 claimed2 = rsa.claimRev(address(creditToken));
        uint256 claimable2 = claimed2 > totalOwed ? totalOwed : claimed2;
        assertGe(claimable2, 0); //must actually claim for test to be valid
        assertEq(creditToken.balanceOf(address(rsa)), claimed + claimed2);
        assertEq(rsa.claimableAmount(), claimable + claimable2); // updated claimable properly
    }


    function test_repay_partialAmountsMultipleTimes(uint256 _revenue) public {
        _depositRSA(lender, rsa);
        uint256 stillOwed = totalOwed;
        uint256 totalRevenue;
        while(stillOwed > 0) {
            assertEq(stillOwed, rsa.totalOwed());
            uint256 revenue = bound(_revenue, initialPrincipal / 5, initialPrincipal / 3);
            _generateRevenue(revenueContract, creditToken, revenue);
            
            uint256 claimed = rsa.claimRev(address(creditToken));
            // update testing param
            totalRevenue += claimed;
            if(claimed > stillOwed) {
                stillOwed = 0;
            } else {
                stillOwed -= claimed;
            }
            // clear operator tokens so _assertSpigot in _generateRevenue passes on multiple invocations
            hoax(operator);
            spigot.claimOperatorTokens(address(creditToken));

            // rsa.repay(); // claimRev auto calls repay() for us
            // TODO test actual repay()?
            // ensure we have tokens that we think were repaid
            assertEq(creditToken.balanceOf(address(rsa)), totalRevenue);
        }
    }

    function test_repay_mustCapRepaymentToToalOwed() public {
        // semantic wrapper
        test_repay_fullAmountMultipleTimes();
    }

    function test_repay_fullAmountMultipleTimes() public {
        _depositRSA(lender, rsa);

        _generateRevenue(revenueContract, creditToken, MAX_REVENUE);
        uint256 claimed = rsa.claimRev(address(creditToken));

        assertEq(0, rsa.totalOwed());
        assertEq(creditToken.balanceOf(address(rsa)), claimed);
        assertGe(creditToken.balanceOf(address(rsa)), totalOwed);

        // clear operator tokens so _assertSpigot in _generateRevenue passes on multiple invocations
        hoax(operator);
        spigot.claimOperatorTokens(address(creditToken));

        _generateRevenue(revenueContract, creditToken, MAX_REVENUE);
        uint256 claimed2 = rsa.claimRev(address(creditToken));

        assertEq(0, rsa.totalOwed());
        assertEq(totalOwed, rsa.claimableAmount());
        assertEq(creditToken.balanceOf(address(rsa)), claimed + claimed2);
        assertGe(claimed + claimed2, totalOwed);

        // rsa.repay(); // claimRev auto calls repay() for us
        // TODO test actual repay()?

        // clear operator tokens so _assertSpigot in _generateRevenue passes on multiple invocations
        hoax(operator);
        spigot.claimOperatorTokens(address(creditToken));
    }

    /// @dev invariant
    function invariant_repay_mustHaveClaimableAmountAsMinimumCreditTokenBalance() public {
        assertGe(creditToken.balanceOf(address(rsa)), rsa.claimableAmount());
        assertLe(rsa.claimableAmount(), totalOwed);
    }

    function test_addSpigot_mustRevertIfNoDebt() public {
        address _revContract = vm.addr(0xdebf);
        (uint8 split, , bytes4 _transferFunc) = spigot.getSetting(_revContract);
         // ensure contract uninitialized and acutally setting new split
        assertEq(split, 0);
        assertEq(_transferFunc, bytes4(0));

        vm.startPrank(lender);
        vm.expectRevert(IRevenueShareAgreement.NotLender.selector);
        rsa.addSpigot(_revContract, claimPushPaymentFunc, transferOwnerFunc);
        vm.stopPrank();
    }

    /// @dev invariant
    function test_addSpigot_mustUseInitializedRevenueSplit() public {
        address _revContract = vm.addr(0xdebf);
        (uint8 split, , bytes4 _transferFunc) = spigot.getSetting(_revContract);
         // ensure contract uninitialized and acutally setting new split
        assertEq(split, 0);
        assertEq(_transferFunc, bytes4(0));

        _depositRSA(lender, rsa);
        vm.startPrank(lender);
        rsa.addSpigot(_revContract, claimPushPaymentFunc, transferOwnerFunc);
        vm.stopPrank();
        (uint8 split2, , bytes4 _transferFunc2) = spigot.getSetting(_revContract);
        assertEq(split2, lenderRevenueSplit);
        assertEq(_transferFunc2, transferOwnerFunc);
    }

    function test_addSpigot_mustBeLender() public {
        address _revContract = vm.addr(0xdebf);
        (uint8 split, , bytes4 _transferFunc) = spigot.getSetting(_revContract);
         // ensure contract uninitialized and acutally setting new split
        assertEq(split, 0);
        assertEq(_transferFunc, bytes4(0));
        
        _depositRSA(lender, rsa);
        vm.startPrank(lender);
        rsa.addSpigot(_revContract, claimPushPaymentFunc, transferOwnerFunc);
        vm.stopPrank();
        (uint8 split2, , bytes4 _transferFunc2) = spigot.getSetting(_revContract);
        assertEq(split2, lenderRevenueSplit);
        assertEq(_transferFunc2, transferOwnerFunc);
    }


    /// @dev invariant
    function test_addSpigot_updatesCorrectRevenueContract() public {
        // semantic wrapper since both tests check same thing by default
        test_addSpigot_mustUseInitializedRevenueSplit();
    }

    function test_updateWhitelist_mustBeLender() public {
        bytes4 operateFunc = bytes4(0x12345678);
        
        // no lender pre deposit so fails
        vm.expectRevert(IRevenueShareAgreement.NotLender.selector);
        rsa.updateWhitelist(operateFunc, true);

        // set lender in contract
        _depositRSA(lender, rsa);
        
        vm.startPrank(lender);
        rsa.updateWhitelist(operateFunc, true);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectRevert(IRevenueShareAgreement.NotLender.selector);
        rsa.updateWhitelist(operateFunc, true);
        vm.stopPrank();

        vm.startPrank(rando);
        vm.expectRevert(IRevenueShareAgreement.NotLender.selector);
        rsa.updateWhitelist(operateFunc, true);
        vm.stopPrank();
    }

    function test_updateWhitelist_mustUpdateSpigot() public {
        bytes4 operateFunc = bytes4(0x12345678);
        assertEq(spigot.isWhitelisted(operateFunc), false);
        
        // no lender pre deposit so fails
        vm.expectRevert(IRevenueShareAgreement.NotLender.selector);
        rsa.updateWhitelist(operateFunc, true);
        assertEq(spigot.isWhitelisted(operateFunc), false);

        // set lender in contract
        _depositRSA(lender, rsa);
        
        vm.startPrank(lender);
        rsa.updateWhitelist(operateFunc, true);
        vm.stopPrank();
        assertEq(spigot.isWhitelisted(operateFunc), true);
    }

    function test_setRevenueSplit_mustUseInitializedRevenueSplit() public {
        uint8 badSplit = 10;
        address _revContract = _addRevenueContract(spigot, address(rsa), address(revenueToken), badSplit, claimPushPaymentFunc, transferOwnerFunc);
        (uint8 split, , bytes4 _transferFunc) = spigot.getSetting(_revContract);

         // ensure contract uninitialized and acutally setting new split
        assertEq(split, badSplit);
        // assertEq(_transferFunc, bytes4(0)); // cant know rev contract addres to check before we deploy, ideally we would check this

        rsa.setRevenueSplit(_revContract);
        (uint8 split2, , bytes4 _transferFunc2) = spigot.getSetting(_revContract);
        assertEq(split2, lenderRevenueSplit);
        assertEq(_transferFunc2, transferOwnerFunc);
    }

    function test_setRevenueSplit_anyoneAnytime(uint8 _badRevenueSplit) public {
        address[3] memory claimers = [rando, borrower, lender];
        uint8 badSplit = uint8(bound(_badRevenueSplit, 0, SpigotLib.MAX_SPLIT));

        for(uint256 i; i < 3; i++) {
            // init new Revenue Contract and give it a bad split
            address _revContract = _addRevenueContract(spigot, address(rsa), address(revenueToken), badSplit, claimPushPaymentFunc, transferOwnerFunc);
            (uint8 split, , bytes4 _transferFunc) = spigot.getSetting(_revContract);

            // ensure contract uninitialized and acutally setting new split
            assertEq(split, badSplit);
            // assertEq(_transferFunc, bytes4(0)); // cant know rev contract addres to check before we deploy, ideally we would check this
            hoax(claimers[i]);
            rsa.setRevenueSplit(_revContract);
            (uint8 split2, , bytes4 _transferFunc2) = spigot.getSetting(_revContract);
            assertEq(split2, lenderRevenueSplit);
            assertEq(_transferFunc2, transferOwnerFunc);
            vm.stopPrank();
        }
    }


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
    // test cant sweep() creditToken greater than rsa.totalSupply()  (claimabe amount invariant should cover this)!!!!



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
    function test_initiateOrder_mustUseHardcodedOrderParams() public {
        _depositRSA(lender, rsa);

        address sellToken = address(revenueToken);
        uint32 deadline = uint32(block.timestamp + 100 days);

        GPv2Order.Data memory expectedOrder = rsa.generateOrder(sellToken, 1, 0, deadline);
        bytes32 expectedHash = expectedOrder.hash(COWSWAP_DOMAIN_SEPARATOR);

        vm.startPrank(lender);
        bytes32 orderHash = rsa.initiateOrder(sellToken, 1, 0, deadline);
        vm.stopPrank();
        
        assertEq(orderHash, expectedHash);
    }


    /// @dev invariant
    function test_generateOrder_mustUseHardcodedOrderParams() public {
        _depositRSA(lender, rsa);

        address sellToken = address(revenueToken);
        address buyToken = address(creditToken);
        uint32 deadline = uint32(block.timestamp + 100 days);

         GPv2Order.Data memory expectedOrder = GPv2Order.Data({
            kind: GPv2Order.KIND_SELL,
            receiver: address(rsa), // hardcode so trades are trustless 
            sellToken: sellToken,  // hardcode so trades are trustless 
            buyToken: buyToken,
            sellAmount: 1,
            buyAmount: 0,
            feeAmount: 0,
            validTo: deadline,
            appData: 0,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        bytes32 expectedHash = expectedOrder.hash(COWSWAP_DOMAIN_SEPARATOR);

        GPv2Order.Data memory order = rsa.generateOrder(sellToken, 1, 0, deadline);
        bytes32 orderHash = order.hash(COWSWAP_DOMAIN_SEPARATOR);
        
        assertEq(expectedHash, orderHash);
    }


    /// @dev invariant
    function test_generateOrder_mustReturnCowswapOrderFormat() public {
        // semantic wrapper
        // we  already manually import GPv2 library and check against generateOrder
        test_generateOrder_mustUseHardcodedOrderParams();
    }

    function test_initiateOrder_mustOwnSellAmount() public {
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
        bytes32 orderId = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days)).hash(COWSWAP_DOMAIN_SEPARATOR);
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

    /********************* EIP-2981 Order Verification *********************/

    function test_verifySignature_mustInitiateOrderFirst() public {
        GPv2Order.Data memory order = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days));
        bytes32 expectedOrderId = order.hash(COWSWAP_DOMAIN_SEPARATOR);
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

    // TODO!!! need to test that the hardcoded order params that isValidSignature never passes if any of those conditions are met


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
        bytes32 orderId = rsa.generateOrder(address(revenueToken), 1, 0, uint32(block.timestamp + 100 days)).hash(COWSWAP_DOMAIN_SEPARATOR);
        assertEq(rsa.orders(orderId), 0);

        vm.startPrank(lender);
        vm.expectEmit(true, true, true, true, address(rsa));
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
        creditToken.mint(_lender, _rsa.initialPrincipal());
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
        
        return _assertSpigotSplits(address(_token), _amount, split);
    }


    /**
     * @dev sends tokens through spigot and makes claimable for owner and operator
     */
    function _tradeRevenue(
        RevenueToken _revenueToken,
        uint256 _minRevenueSold,
        uint256 _minCreditsBought
    ) internal returns(uint256 tokensBought) {
        // dont actually need to initiate trade since we can update EVM state manually
        // keep to document flow and hopefully check bugs related to process
        hoax(lender);
        rsa.initiateOrder(address(_revenueToken), _minRevenueSold, _minCreditsBought, uint32(MAX_UINT));

        creditToken.mint(address(rsa), _minCreditsBought);
        _revenueToken.burnFrom(address(rsa), _minRevenueSold);

        return _minCreditsBought;
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
    function _getMaxRevenue(uint256 _totalRevenue) internal pure returns(uint256, uint256) {
        if(_totalRevenue > MAX_REVENUE) return(MAX_REVENUE, _totalRevenue - MAX_REVENUE);
        return (_totalRevenue, 0);
    }

    /**
     * @dev helper func to check revenue payment streams to `ownerTokens` and `operatorTokens` happened and Spigot is accounting properly.
    */
    function _assertSpigotSplits(address _token, uint256 _totalRevenue, uint8 _split)
        internal
        returns(uint256 ownerTokens, uint256 operatorTokens)
    {
        (uint256 maxRevenue, uint256 overflow) = _getMaxRevenue(_totalRevenue);
        ownerTokens = maxRevenue * _split / 100;
        operatorTokens = maxRevenue - ownerTokens;
        uint256 spigotBalance = _token == Denominations.ETH ?
            address(spigot).balance :
            RevenueToken(_token).balanceOf(address(spigot));

        uint256 roundingFix = spigotBalance - (ownerTokens + operatorTokens + overflow);
        if(overflow > 0) {
            assertLe(roundingFix, 1, "Spigot rounding error too large");
        }

        assertEq(
            spigot.getOwnerTokens(_token),
            ownerTokens,
            'Invalid Owner amount for spigot revenue'
        );

        assertEq(
            spigot.getOperatorTokens(_token),
            operatorTokens,
            'Invalid Operator payment amount for spigot revenue'
        );

        assertEq(
            spigotBalance,
            ownerTokens + operatorTokens + overflow + roundingFix, // revenue over max stays in contract unnaccounted
            'Spigot balance vs escrow + overflow mismatch'
        );
    }


    // dummy functions to get interfaces for RSA and SPpigot

    function claimRevenue(
        address revenueContract,
        address token,
        bytes calldata data
    ) external returns (uint256 claimed) { return 0; }

    function operate(address revenueContract, bytes calldata data) external returns (bool) {
        return  true;
    }

    // owner funcs

    function claimOwnerTokens(address token) external returns (uint256 claimed) {
        return 0;
    }

    function claimOperatorTokens(address token) external returns (uint256 claimed) {
        return 0;
    }

    function addSpigot(address revenueContract, Setting memory setting) external returns (bool) {
        return  true;
    }

    function removeSpigot(address revenueContract) external returns (bool) {
        return  true;
    }

    // stakeholder funcs

    function updateOwnerSplit(address revenueContract, uint8 ownerSplit) external returns (bool) {
        return  true;
    }

    function updateOwner(address newOwner) external returns (bool) {
        return  true;
    }

    function updateOperator(address newOperator) external returns (bool) {
        return  true;
    }

    function updateWhitelistedFunction(bytes4 func, bool allowed) external returns (bool) {
        return  true;
    }

    // Getters
    function owner() external view returns (address) {
        return address(0);
    }

    // function operator() external view returns (address) {
    //     return address(0);
    // }

    function isWhitelisted(bytes4 func) external view returns (bool) {
        return  true;
    }

    function getOwnerTokens(address token) external view returns (uint256) {
        return 0;
    }

    function getOperatorTokens(address token) external view returns (uint256) {
        return 0;
    }

    function getSetting(
        address revenueContract
    ) external view returns (uint8 split, bytes4 claimFunc, bytes4 transferFunc) {
        return (0, bytes4(0), bytes4(0));
    }
}
