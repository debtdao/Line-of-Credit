pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import {RevenueToken} from "../mock/RevenueToken.sol";
import {LineFactory} from "../modules/factories/LineFactory.sol";
import {ModuleFactory} from "../modules/factories/ModuleFactory.sol";
import {ILineFactory} from "../interfaces/ILineFactory.sol";
import {ISecuredLine} from "../interfaces/ISecuredLine.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {ISpigot} from "../interfaces/ISpigot.sol";

import {IEscrow} from "../interfaces/IEscrow.sol";
import {SecuredLine} from "../modules/credit/SecuredLine.sol";
import {Spigot} from "../modules/spigot/Spigot.sol";
import {Escrow} from "../modules/escrow/Escrow.sol";
import {LineLib} from "../utils/LineLib.sol";
import {MutualConsent} from "../utils/MutualConsent.sol";

interface Events {
    event Borrow(bytes32 indexed id, uint256 indexed amount);
    event MutualConsentRegistered(bytes32 _consentHash);
    event MutualConsentRevoked(address indexed user, bytes32 _toRevoke);
}

contract MutualConsentTest is Test, Events {
    SecuredLine line;
    Spigot spigot;
    Escrow escrow;
    LineFactory lineFactory;
    ModuleFactory moduleFactory;

    RevenueToken supportedToken1;

    address oracle;
    address arbiter;
    address borrower;
    address swapTarget;
    address lender;
    uint256 ttl = 90 days;
    address line_address;
    address spigot_address;
    address escrow_address;

    uint256 mintAmount = 100 ether;
    uint256 MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 minCollateralRatio = 1 ether; // 100%
    uint128 dRate = 100;
    uint128 fRate = 1;

    constructor() {
        oracle = address(0xdebf);
        arbiter = address(0xf1c0);
        lender = address(0xfde0);
        borrower = address(0xbA05);
        swapTarget = address(0xb0b0);

        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(
            address(moduleFactory),
            arbiter,
            oracle,
            swapTarget
        );

        line_address = lineFactory.deploySecuredLine(borrower, ttl);

        line = SecuredLine(payable(line_address));

        spigot_address = address(line.spigot());
        spigot = Spigot(payable(spigot_address));

        escrow_address = address(line.escrow());
        escrow = Escrow(payable(escrow_address));

        supportedToken1 = new RevenueToken();
    }

    function test_revoking_addCredit_invalid_consent_fails() public {
        address token = address(supportedToken1);
        uint256 amount = 1 ether;

        // add consent as borrower
        vm.startPrank(borrower);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

        // derive the expected consent hash
        bytes memory invalidMsgData = _generateMutualConsentMessageData(
            ILineOfCredit.addCredit.selector,
            dRate,
            fRate,
            amount,
            token,
            makeAddr("randomLender")
        );
        emit log_named_bytes("invalid msg data:", invalidMsgData);
        emit log_named_uint("bytes length", invalidMsgData.length);
        bytes32 nonExistentHash = _simulateMutualConstentHash(
            invalidMsgData,
            borrower
        );
        emit log_named_bytes32("invalid msg hash:", nonExistentHash);

        vm.startPrank(borrower);
        vm.expectRevert(MutualConsent.InvalidConsent.selector);
        line.revokeConsent(invalidMsgData);

        vm.stopPrank();

        // should fail revoking consent as different user (with correct data)
        // vm.startPrank(lender);
        // vm.expectRevert(MutualConsent.NotUserConsent.selector);
        // line.revokeConsent(
        //     ILineOfCredit.addCredit.selector,
        //     dRate,
        //     fRate,
        //     amount,
        //     token,
        //     lender
        // );
        // vm.stopPrank();
    }

    function test_can_revoke_mutualConsent_for_addCredit_as_borrower() public {
        /*

        // succeed revoking consent
        vm.expectEmit(true,false,false,true, address(line));
        emit MutualConsentRevoked(expectedHash); 
        line.revokeConsent(ILineOfCredit.addCredit.selector, dRate, fRate, amount, token, lender);
        vm.stopPrank();



        // lender addCredit should create a new id
        vm.startPrank(lender);
        expectedHash =_simulateMutualConstentHash(ILineOfCredit.addCredit.selector, dRate, fRate, amount, token, lender, lender);
        vm.expectEmit(true,false,false,true,address(line));
        emit MutualConsentRegistered(expectedHash); // we dont know the hash id
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
        */
    }

    /*/////////////////////////////////////////////////////
                            UTILS
    /////////////////////////////////////////////////////*/

    function _generateMutualConsentMessageData(
        bytes4 fnSelector,
        uint128 drate,
        uint128 frate,
        uint256 amount,
        address token,
        address lender
    ) internal returns (bytes memory msgData) {
        bytes memory reconstructedArgs = abi.encode(
            drate,
            frate,
            amount,
            token,
            lender
        );
        msgData = abi.encodePacked(fnSelector, reconstructedArgs);
    }

    function _simulateMutualConstentHash(
        bytes memory reconstructedMsgData,
        address msgSender
    ) internal returns (bytes32) {
        return keccak256(abi.encodePacked(reconstructedMsgData, msgSender));
    }
}
