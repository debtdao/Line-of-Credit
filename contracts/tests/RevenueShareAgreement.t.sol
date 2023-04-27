pragma solidity 0.8.16;

import "forge-std/Test.sol";
import { RevenueShareAgreement } from "../modules/credit/RevenueShareAgreement.sol";
import { RSAFactory } from "../modules/factories/RSAFactory.sol";
import {Spigot} from "../modules/spigot/Spigot.sol";

import {RevenueToken} from "../mock/RevenueToken.sol";
import {SimpleRevenueContract} from "../mock/SimpleRevenueContract.sol";
import {Denominations} from "chainlink/Denominations.sol";

import {ISpigot} from "../interfaces/ISpigot.sol";

contract RevenueShareAgreementTest is Test {
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
    bytes4 constant opsFunc =
        SimpleRevenueContract.doAnOperationsThing.selector;
    bytes4 constant transferOwnerFunc =
        SimpleRevenueContract.transferOwnership.selector;
    bytes4 constant claimPullPaymentFunc =
        SimpleRevenueContract.claimPullPayment.selector;
    bytes4 constant claimPushPaymentFunc = bytes4(0);

    ISpigot.Setting[] private s;

    // RSA + Spigot stakeholder
    RSAFactory factory;
    RevenueShareAgreement private rsa;
    address private operator;
    address private borrower;
    address private lender;
    uint256 private initialPrincipal = 10_000 * 1e18;
    uint256 private totalOwed = 13_000 * 1e18;
  

    function setUp() public {
        operator = vm.addr(2);
        borrower = vm.addr(3);
        lender = vm.addr(4);
        factory = new RSAFactory();
        
        revenueToken = new RevenueToken();
        creditToken = new RevenueToken();

        _initSpigot(
            address(revenueToken),
            100,
            claimPushPaymentFunc,
            transferOwnerFunc
        );

        rsa = _initRSA(
            address(spigot),
            address(creditToken),
            lender,
            initialPrincipal,
            totalOwed
        );

        // TODO find some good revenue contracts to mock and deploy
    }


    function test_deposit_lenderMustDepositInitialPrincipal() public {
        uint256 balance1 = creditToken.balanceOf(lender);
        vm.startPrank(lender);
        rsa.deposit();
        uint256 balance2 = creditToken.balanceOf(lender);
        assertEq(balance1 - balance2, rsa.initialPrincipal());
        vm.stopPrank();
    }

    function test_deposit_borrowerGetsInitialPrincipalOnDeposit() public {
        uint256 balance1 = creditToken.balanceOf(borrower);
        vm.startPrank(lender);
        rsa.deposit();
        uint256 balance2 = creditToken.balanceOf(borrower);
        assertEq(balance2 - balance1, rsa.initialPrincipal());
        vm.stopPrank();
    }

    /*********************
    **********************
    
    CowSwap Market Order Creation
    
    **********************
    *********************/

    function test_initiateOrder_returnsOrderHash() public {
        vm.startPrank(lender);
        rsa.deposit();
        bytes32 orderHash = rsa.initiateOrder(address(revenueToken), 1, 0, block.timestamp + 100 days);
        assertTrue(orderHash != bytes32(0));
        vm.stopPrank();
    }

    function invariant_initiateOrder_mustSellOver1Token() public {
        vm.startPrank(lender);
        rsa.deposit();
        vm.expectRevert("Invalid trade amount");
        rsa.initiateOrder(address(revenueToken), 0, 0, block.timestamp + 100 days);
        vm.stopPrank();
    }

    function invariant_initiateOrder_cantTradeIfNoDebt() public {
        // havent deposited so no debt
        vm.expectRevert("Trade not required");
        rsa.initiateOrder(address(revenueToken), 1, 0, block.timestamp + 100 days);
        hoax(lender);
        rsa.deposit();
    }

    function invariant_initiateOrder_cantSellCreditToken() public {
        vm.startPrank(lender);
        rsa.deposit();
        vm.expectRevert("Cant sell token being bought");
        rsa.initiateOrder(address(creditToken), 1, 0, block.timestamp + 100 days);
        vm.stopPrank();
    }

    function test_initiateOrder_lenderOrBorrowerCanSubmit() public {
        vm.startPrank(lender);
        rsa.deposit();
        rsa.initiateOrder(address(revenueToken), 1, 0, block.timestamp + 100 days);
        vm.stopPrank();
        hoax(borrower);
        rsa.initiateOrder(address(revenueToken), 1, 0, block.timestamp + 100 days);
        
        hoax(vm.addr(69));
        vm.expectRevert("Caller must be stakeholder");
        rsa.initiateOrder(address(revenueToken), 1, 0, block.timestamp + 100 days);
    }

    /*********************
    **********************
    
    EIP-2981 Order Verification
    
    **********************
    *********************/

    function invariant_verifySignature_mustUseERC20Balance() public {
        revert();
    }

    function invariant_verifySignature_mustBuyCreditToken() public {
        revert();
    }

    function invariant_verifySignature_mustBeSellOrder() public {
        revert();
    }

    function invariant_verifySignature_mustSignOrderFromCowContract() public {
        revert();
    }


    /**
     * @dev Creates a new Revenue Share Agreement mints token to lender and approves to RSA
    * @param _spigot address of spigot to use for revenue share
    * @param _token address of token being lent
    * @param _lender address that will lend to RSA
    * @param _initialPrincipal amount of tokens to lend
    * @param _totalOwed total amount of tokens owed to lender through RSA
     */
    function _initRSA(
        address _spigot,
        address _token,
        address _lender,
        uint256 _initialPrincipal,
        uint256 _totalOwed
    ) internal returns(RevenueShareAgreement newRSA) {
        address _newRSA = factory.createRSA(
            _spigot,
            borrower,
            _token,
            lenderRevenueSplit,
            _initialPrincipal,
            _totalOwed,
            "RSA Revenue Stream Token",
            "rsaCLAIM"
        );

        creditToken.mint(_lender, _initialPrincipal);
        hoax(_lender);
        creditToken.approve(_newRSA, type(uint256).max);
        return RevenueShareAgreement(_newRSA);
    }

    /**
     * @dev Helper function to initialize new Spigots with different params to test functionality
     */
    function _initSpigot(
        address _token,
        uint8 _split,
        bytes4 _claimFunc,
        bytes4 _newOwnerFunc
    ) internal {
        spigot = new Spigot(borrower, operator);

        // deploy new revenue contract with settings
        revenueContract = address(new SimpleRevenueContract(borrower, _token));

        _addRevenueContract(spigot, borrower, revenueContract, _split, _claimFunc, _newOwnerFunc);
    }


    /**
     * @dev Helper function to initialize new Spigots with different params to test functionality
     */
    function _addRevenueContract(
        Spigot _spigot,
        address _owner,
        address _revenueContract,
        uint8 _split,
        bytes4 _claimFunc,
        bytes4 _newOwnerFunc
    ) internal {
        // deploy new revenue contract with settings

        settings = ISpigot.Setting(_split, _claimFunc, _newOwnerFunc);

        hoax(_owner);
        // add spigot for revenue contract
        require(
            _spigot.addSpigot(revenueContract, settings),
            "Failed to add spigot"
        );

        // give spigot ownership to claim revenue
        _revenueContract.call(
            abi.encodeWithSelector(_newOwnerFunc, address(spigot))
        );
    }
    // Claiming functions


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
}
