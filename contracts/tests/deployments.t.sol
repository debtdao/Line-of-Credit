pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {Denominations} from "chainlink/Denominations.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {LineLib} from "../utils/LineLib.sol";
import {CreditLib} from "../utils/CreditLib.sol";
import {CreditListLib} from "../utils/CreditListLib.sol";
import {MutualConsent} from "../utils/MutualConsent.sol";
import {LineOfCredit} from "../modules/credit/LineOfCredit.sol";

import {Escrow} from "../modules/escrow/Escrow.sol";
import {EscrowLib} from "../utils/EscrowLib.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {RevenueToken} from "../mock/RevenueToken.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";

contract LineTest is Test {
    uint256 mainnetFork;
    uint256 initialBlockNumber = 17090100;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {

        mainnetFork = vm.createFork(MAINNET_RPC_URL, initialBlockNumber);
        vm.selectFork(mainnetFork);

    }

    function test_generateRefractionPositionData() public returns (bytes32 positionID, bytes memory proposalData) {
        address line_refraction = address(0xD0062FdC7a60BA083Daf534e09877f7407359DB2);

        address borrower_refractiondao = address(0xCBfa3c438EBb86FF17b075a0a0b6f15a08DAFEA8);
        address lender_ethos = address(0x18dBEaD7db371FD1b20EEcA64cE62A8c0fF54Ae2);
        address token_lusd = address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
        

        bytes memory proposalData = abi.encodeWithSelector(
            ILineOfCredit.addCredit.selector,
            900, // 9% in bps
            900,
            30000000000000000000000,
            token_lusd,
            lender_ethos
        );

        bytes32 positionID = keccak256(abi.encode(
            line_refraction,
            lender_ethos,
            token_lusd
        ));

        emit log_named_bytes32("positionID", positionID);
        emit log_named_bytes("proposal Data", proposalData);

        (bool success1, bytes memory errorData) = address(line_refraction).call(proposalData);
        if (!success1) {
            emit log_named_bytes("proposal error", errorData);
        }
        if (positionID == bytes32(0)) {
            emit log_named_string("proposalID", "Proposal not accepted new proposal creted.");
        }

        emit log_named_bytes32("proposal created? (should be non 0x)", bytes32(errorData));
        emit log_named_bytes("proposal error data", errorData);


        bytes memory borrowData = abi.encodeWithSelector(ILineOfCredit.borrow.selector, positionID, 30000000000000000000000);
        emit log_named_bytes("borrow Data", borrowData);

        emit log_named_uint("pre borrow balance", IERC20(token_lusd).balanceOf(borrower_refractiondao));
        (bool success2, bytes memory errorData2) = address(line_refraction).call(borrowData);
        if (!success2) {
            emit log_named_bytes("borrow error", errorData2);
        }
        emit log_named_uint("post borrow balance", IERC20(token_lusd).balanceOf(borrower_refractiondao));
        emit log_named_bytes("borrow error data", errorData2);


        return (positionID, proposalData);
    }
}