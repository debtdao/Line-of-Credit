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

import {SimpleOracle} from "../mock/SimpleOracle.sol";

interface Events {
    event Borrow(bytes32 indexed id, uint256 indexed amount);
    event MutualConsentRegistered(bytes32 _proposalId, address _nonCaller);
    event MutualConsentRevoked(bytes32 _proposalId);
}

contract MutualConsentTest is Test, Events {
    SecuredLine line;
    Spigot spigot;
    Escrow escrow;
    SimpleOracle oracle;
    LineFactory lineFactory;
    ModuleFactory moduleFactory;

    RevenueToken supportedToken1;
    RevenueToken supportedToken2;

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

    uint256 amount = 1 ether;
    address token;

    constructor() {
        arbiter = address(0xf1c0);
        lender = address(0xfde0);
        borrower = address(0xbA05);
        swapTarget = address(0xb0b0);

        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        token = address(supportedToken1);
        oracle = new SimpleOracle(
            address(supportedToken1),
            address(supportedToken2)
        );

        moduleFactory = new ModuleFactory();
        lineFactory = new LineFactory(
            address(moduleFactory),
            arbiter,
            address(oracle),
            payable(swapTarget)
        );

        line_address = lineFactory.deploySecuredLine(borrower, ttl);

        line = SecuredLine(payable(line_address));

        spigot_address = address(line.spigot());
        spigot = Spigot(payable(spigot_address));

        escrow_address = address(line.escrow());
        escrow = Escrow(payable(escrow_address));
    }

    function setUp() public {
        // add consent as borrower
        vm.startPrank(borrower);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

        _mintAndApprove();
    }

    /*/////////////////////////////////////////////////////
                            addCredit
    /////////////////////////////////////////////////////*/

    function test_addCredit_revoking_invalid_consent_fails() public {
        // derive the expected consent hash
        bytes
            memory invalidMsgData = _generateAddCreditMutualConsentMessageData(
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
    }

    function test_addCredit_cant_revoke_consent_as_malicious_user()
        public
    {
        // should fail revoking consent as different user (with correct data)

        bytes memory msgData = _generateAddCreditMutualConsentMessageData(
            ILineOfCredit.addCredit.selector,
            dRate,
            fRate,
            amount,
            token,
            lender
        );

        bytes32 expectedHash = _simulateMutualConstentHash(msgData, borrower);

        vm.startPrank(lender);
        vm.expectRevert(MutualConsent.InvalidConsent.selector);
        line.revokeConsent(msgData);
        vm.stopPrank();
    }


    function test_addCredit_revoking_consent_must_delete_consenst_hash() external {
        bytes memory msgData = _generateAddCreditMutualConsentMessageData(
            ILineOfCredit.addCredit.selector,
            dRate,
            fRate,
            amount,
            token,
            lender
        );
        bytes32 expectedHash = _simulateMutualConstentHash(msgData, borrower);

        vm.startPrank(borrower);
        vm.expectEmit(true, false, false, true, address(line));
        emit MutualConsentRevoked(expectedHash);
        line.revokeConsent(msgData);

        assertEq(line.mutualConsentProposals(expectedHash), address(0));
    }

    function test_addCredit_calling_function_after_revocation_registers_new_consent() external {
        bytes memory msgData = _generateAddCreditMutualConsentMessageData(
            ILineOfCredit.addCredit.selector,
            dRate,
            fRate,
            amount,
            token,
            lender
        );


        vm.startPrank(borrower);
        line.revokeConsent(msgData);
        vm.stopPrank();

        vm.startPrank(lender);
        vm.expectEmit(true,true,false,true, address(line));
        bytes32 expectedHash = _simulateMutualConstentHash(msgData, lender);
        emit MutualConsentRegistered(expectedHash, borrower);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

    }

    function test_addCredit_revoking_consent_with_invalid_msg_data_fails()
        public
    {
        vm.startPrank(borrower);

        bytes memory msgData = _generateAddCreditMutualConsentMessageData(
            ILineOfCredit.addCredit.selector,
            dRate,
            fRate,
            amount,
            token,
            lender
        );

        bytes memory invalidMsgData = abi.encodePacked(msgData, uint256(5));

        vm.expectRevert(
            MutualConsent.UnsupportedMutualConsentFunction.selector
        );
        line.revokeConsent(invalidMsgData);
        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////
                            setRate
    /////////////////////////////////////////////////////*/

    function test_setRates_can_revoke_consent() public {
        // first complete adding credit
        vm.startPrank(lender);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

        bytes32 id = line.ids(0);

        emit log_named_bytes32("line id: ", id);

        uint128 newFrate = uint128(1 ether);
        uint128 newDrate = uint128(1 ether);

        bytes memory msgData = _generateSetRatesMutualConsentMessageData(
            ILineOfCredit.setRates.selector,
            id,
            newFrate,
            newDrate
        );
        // set the rates as the borrower, thus registering mutual consent, and then revoke it
        vm.startPrank(borrower);
        line.setRates(id, newFrate, newDrate);
        bytes32 expectedHash = _simulateMutualConstentHash(msgData, borrower);
        vm.expectEmit(true, false, false, true, address(line));
        emit MutualConsentRevoked(expectedHash);
        line.revokeConsent(msgData);
        vm.stopPrank();

        // now set rates and register mutual consent as lender
        vm.startPrank(lender);
        expectedHash = _simulateMutualConstentHash(msgData, lender);
        vm.expectEmit(true, true, false, true, address(line));
        emit MutualConsentRegistered(expectedHash, borrower);
        line.setRates(id, newFrate, newDrate);
        vm.stopPrank();

        /*
        (uint128 currentDrate, uint128 currentFrate, ) = line
            .interestRate()
            .rates(id);
        assertEq(currentDrate, newDrate);
        assertEq(currentFrate, newFrate);
        */
    }

    function test_setRates_fail_to_revoke_consent_as_other_signer() public {
        // first complete adding credit
        vm.startPrank(lender);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

        bytes32 id = line.ids(0);

        emit log_named_bytes32("line id: ", id);

        uint128 newFrate = uint128(1 ether);
        uint128 newDrate = uint128(1 ether);

        vm.startPrank(borrower);
        line.setRates(id, newFrate, newDrate);
        vm.stopPrank();

        bytes memory msgData = _generateSetRatesMutualConsentMessageData(
            ILineOfCredit.setRates.selector,
            id,
            newFrate,
            newDrate
        );

        // attempt to revoke consent (should fail)
        vm.startPrank(lender);
        vm.expectRevert(MutualConsent.InvalidConsent.selector);
        line.revokeConsent(msgData);
        vm.stopPrank();
    }

    function test_setRates_revoke_consent_with_zero_bytes_fails() public {
        vm.startPrank(lender);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

        bytes32 id = line.ids(0);

        emit log_named_bytes32("line id: ", id);

        uint128 newFrate = uint128(1 ether);
        uint128 newDrate = uint128(1 ether);

        vm.startPrank(borrower);
        line.setRates(id, newFrate, newDrate);

        bytes memory msgData = bytes("");

        vm.expectRevert(
            MutualConsent.UnsupportedMutualConsentFunction.selector
        );
        line.revokeConsent(msgData);
        vm.stopPrank();
    }

    function test_setRates_revoke_consent_as_malicious_user() public {
        vm.startPrank(lender);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

        bytes32 id = line.ids(0);

        emit log_named_bytes32("line id: ", id);

        uint128 newFrate = uint128(1 ether);
        uint128 newDrate = uint128(1 ether);

        vm.startPrank(borrower);
        line.setRates(id, newFrate, newDrate);
        vm.stopPrank();

        bytes memory msgData = _generateSetRatesMutualConsentMessageData(
            ILineOfCredit.setRates.selector,
            id,
            newFrate,
            newDrate
        );

        // attempt to revoke consent (should fail)
        vm.startPrank(makeAddr("maliciousUser"));
        vm.expectRevert(MutualConsent.InvalidConsent.selector);
        line.revokeConsent(msgData);
        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////
                        increaseCredit
    /////////////////////////////////////////////////////*/

    function test_increaseCredit_can_revoke_consent_as_caller() public {
        vm.startPrank(lender);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
        bytes32 id = line.ids(0);
        emit log_named_bytes32("line id: ", id);

        uint256 amount = 1 ether;

        bytes memory msgData = _generateIncreaseRatesMutualConsentMessageData(
            ILineOfCredit.increaseCredit.selector,
            id,
            amount
        );

        vm.startPrank(borrower);
        line.increaseCredit(id, amount);
        bytes32 expectedHash = _simulateMutualConstentHash(msgData, borrower);
        vm.expectEmit(true, false, false, true, address(line));
        emit MutualConsentRevoked(expectedHash);
        line.revokeConsent(msgData);
        vm.stopPrank();
    }

    function test_increaseCredit_cannot_revoke_consent_as_malicious_user()
        public
    {
        vm.startPrank(lender);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();

        bytes32 id = line.ids(0);

        uint256 amount = 1 ether;

        bytes memory msgData = _generateIncreaseRatesMutualConsentMessageData(
            ILineOfCredit.increaseCredit.selector,
            id,
            amount
        );

        vm.startPrank(borrower);
        line.increaseCredit(id, amount);
        vm.stopPrank();

        vm.startPrank(makeAddr("maliciousUser"));
        vm.expectRevert(MutualConsent.InvalidConsent.selector);
        line.revokeConsent(msgData);
        vm.stopPrank();
    }

    /*/////////////////////////////////////////////////////
                            UTILS
    /////////////////////////////////////////////////////*/

    function _mintAndApprove() internal {
        deal(lender, mintAmount);

        supportedToken1.mint(borrower, mintAmount);
        supportedToken1.mint(lender, mintAmount);

        vm.startPrank(borrower);
        supportedToken1.approve(address(line), MAX_INT);
        vm.stopPrank();

        vm.startPrank(lender);
        supportedToken1.approve(address(line), MAX_INT);
        vm.stopPrank();
    }

    function _generateAddCreditMutualConsentMessageData(
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

    function _generateSetRatesMutualConsentMessageData(
        bytes4 fnSelector,
        bytes32 id,
        uint128 drate,
        uint128 frate
    ) internal returns (bytes memory msgData) {
        bytes memory reconstructedArgs = abi.encode(id, drate, frate);
        msgData = abi.encodePacked(fnSelector, reconstructedArgs);
    }

    function _generateIncreaseRatesMutualConsentMessageData(
        bytes4 fnSelector,
        bytes32 id,
        uint256 amount
    ) internal returns (bytes memory msgData) {
        bytes memory reconstructedArgs = abi.encode(id, amount);
        msgData = abi.encodePacked(fnSelector, reconstructedArgs);
    }

    function _simulateMutualConstentHash(
        bytes memory reconstructedMsgData,
        address msgSender
    ) internal returns (bytes32) {
        return keccak256(abi.encodePacked(reconstructedMsgData, msgSender));
    }
}
