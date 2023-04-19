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
            transferOwnerFunc
        );

        // TODO find some good revenue contracts to mock and deploy
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
        spigot = new Spigot(owner, operator);

        // deploy new revenue contract with settings
        revenueContract = address(new SimpleRevenueContract(owner, _token));

        _addRevenueContract(spigot, revenueContract, _split, _claimFunc, _newOwnerFunc);
    }


    /**
     * @dev Helper function to initialize new Spigots with different params to test functionality
     */
    function _addRevenueContract(
        Spigot _spigot,
        address _revenueContract,
        uint8 _split,
        bytes4 _claimFunc,
        bytes4 _newOwnerFunc
    ) internal {
        // deploy new revenue contract with settings

        settings = ISpigot.Setting(_split, _claimFunc, _newOwnerFunc);

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
