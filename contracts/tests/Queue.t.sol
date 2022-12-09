pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import {Denominations} from "chainlink/Denominations.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {LineLib} from "../utils/LineLib.sol";
import {CreditLib} from "../utils/CreditLib.sol";
import {CreditListLib} from "../utils/CreditListLib.sol";
import {MutualConsent} from "../utils/MutualConsent.sol";
import {InterestRateCredit} from "../modules/interest-rate/InterestRateCredit.sol";
import {LineOfCredit} from "../modules/credit/LineOfCredit.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ILineOfCredit} from "../interfaces/ILineOfCredit.sol";
import {RevenueToken} from "../mock/RevenueToken.sol";
import {SimpleOracle} from "../mock/SimpleOracle.sol";

interface Events {
    event Borrow(bytes32 indexed id, uint256 indexed amount);
    event SetRates(
        bytes32 indexed id,
        uint128 indexed dRate,
        uint128 indexed fRate
    );
}

contract QueueTest is Test, Events {
     SimpleOracle oracle;
    address borrower;
    address arbiter;
    address lender;
    uint256 ttl = 150 days;
    RevenueToken supportedToken1;
    RevenueToken supportedToken2;
    RevenueToken unsupportedToken;
    LineOfCredit line;
    uint256 mintAmount = 100 ether;
    uint256 MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 minCollateralRatio = 1 ether; // 100%
    uint128 dRate = 100;
    uint128 fRate = 1;

    mapping (bytes32 => string) idLabels;

    function setUp() public {
        borrower = address(10);
        arbiter = address(this);
        lender = address(20);

        supportedToken1 = new RevenueToken();
        supportedToken2 = new RevenueToken();
        unsupportedToken = new RevenueToken();

        oracle = new SimpleOracle(
            address(supportedToken1),
            address(supportedToken2)
        );

        line = new LineOfCredit(address(oracle), arbiter, borrower, ttl);
        assertEq(uint256(line.init()), uint256(LineLib.STATUS.ACTIVE));
        _mintAndApprove();
    }


    function test_all_positions_in_queue_of_4_are_closed() public {
        address[] memory tokens = setupQueueTest(2);
        address token3 = tokens[0];
        address token4 = tokens[1];

        vm.startPrank(borrower);
        line.addCredit(dRate, fRate, 1 ether, address(supportedToken1), lender);
        line.addCredit(dRate, fRate, 1 ether, address(supportedToken2), lender);
        line.addCredit(dRate, fRate, 1 ether, address(token3), lender);
        line.addCredit(dRate, fRate, 1 ether, address(token4), lender);
        vm.stopPrank();

        vm.startPrank(lender);
        bytes32 id = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(supportedToken1),
            lender
        );
        bytes32 id2 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(supportedToken2),
            lender
        );
        bytes32 id3 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(token3),
            lender
        );
        bytes32 id4 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(token4),
            lender
        );
        vm.stopPrank();

        _assignQueueLabels();

        assertEq(line.ids(0), id);
        assertEq(line.ids(1), id2);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id4);

        _formatLoggedArrOfIds("initial queue state");

        vm.startPrank(borrower);
        // should now look like [ id3, id, id2, id4]
        line.borrow(id3, 1 ether);
        _formatLoggedArrOfIds("after borrowing from id3");
        assertEq(line.ids(0), id3);
        assertEq(line.ids(1), id2);
        assertEq(line.ids(2), id);
        assertEq(line.ids(3), id4);

        // close the other lines
        line.close(id2);
        _formatLoggedArrOfIds("after closing id2");

        line.close(id);
        _formatLoggedArrOfIds("after closing id");

        line.close(id4);
        _formatLoggedArrOfIds("after closing id4");
        
        // should close remaining id in position ids[0]
        // TODO: what happens when zero available valid ids
        line.depositAndClose();
        _formatLoggedArrOfIds("after depositAndClose");

    }

    function test_positions_move_in_queue_of_4_random_active_line() public {
        address[] memory tokens = setupQueueTest(2);
        address token3 = tokens[0];
        address token4 = tokens[1];

        vm.startPrank(borrower);
        line.addCredit(dRate, fRate, 1 ether, address(supportedToken1), lender);
        line.addCredit(dRate, fRate, 1 ether, address(supportedToken2), lender);
        line.addCredit(dRate, fRate, 1 ether, address(token3), lender);
        line.addCredit(dRate, fRate, 1 ether, address(token4), lender);
        vm.stopPrank();

        vm.startPrank(lender);
        bytes32 id = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(supportedToken1),
            lender
        );
        bytes32 id2 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(supportedToken2),
            lender
        );
        bytes32 id3 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(token3),
            lender
        );
        bytes32 id4 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(token4),
            lender
        );
        vm.stopPrank();

        assertEq(line.ids(0), id);
        assertEq(line.ids(1), id2);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id4);

        hoax(borrower);
        line.borrow(id2, 1 ether);

        assertEq(line.ids(0), id2);
        assertEq(line.ids(1), id);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id4);
        hoax(borrower);

        line.borrow(id4, 1 ether);

        assertEq(line.ids(0), id2);
        assertEq(line.ids(1), id4);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id); // id switches with id4, not just pushed one step back in queue
        hoax(borrower);

        // here id2's position will be closed, then swapped with the next valid line, ie id4 at ids[1]
        line.depositAndClose();

        // The queue doesn't "shift", the null first element is swapped with the next available valid id
        assertEq(line.ids(0), id4);
        assertEq(line.ids(1), bytes32(0));
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id);
    }

    // check that only borrowing from the last possible id will still sort queue properly
    // testing for bug in code where _i is initialized at 0 and never gets updated causing position to go to first position in repayment queue
    function test_positions_move_in_queue_of_4_only_last() public {
        vm.prank(borrower);
        line.addCredit(dRate, fRate, 1 ether, address(supportedToken1), lender);
        vm.prank(lender);
        bytes32 id = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(supportedToken1),
            lender
        );
        vm.prank(borrower);
        line.addCredit(dRate, fRate, 1 ether, address(supportedToken2), lender);
        vm.prank(lender);
        bytes32 id2 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(supportedToken2),
            lender
        );

        address[] memory tokens = setupQueueTest(2);
        address token3 = tokens[0];
        address token4 = tokens[1];

        vm.prank(borrower);
        line.addCredit(dRate, fRate, 1 ether, address(token3), lender);
        vm.prank(lender);
        bytes32 id3 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(token3),
            lender
        );

        vm.prank(borrower);
        line.addCredit(dRate, fRate, 1 ether, address(token4), lender);
        vm.prank(lender);
        bytes32 id4 = line.addCredit(
            dRate,
            fRate,
            1 ether,
            address(token4),
            lender
        );

        assertEq(line.ids(0), id);
        assertEq(line.ids(1), id2);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id4);

        vm.prank(borrower);

        line.borrow(id4, 1 ether);

        assertEq(line.ids(0), id4);
        assertEq(line.ids(1), id2);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id);

        
        vm.prank(borrower);
        line.borrow(id, 1 ether);

        assertEq(line.ids(0), id4);
        assertEq(line.ids(1), id);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id2); // id switches with id4, not just pushed one step back in queue

        vm.prank(borrower);
        line.depositAndRepay(1 wei);

        assertEq(line.ids(0), id4);
        assertEq(line.ids(1), id);
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id2);

        
        vm.startPrank(borrower);
        line.depositAndClose(); // will pay off and close ids[0], and swap next available into the first slot

        assertEq(line.ids(0), id);
        assertEq(line.ids(1), bytes32(0)); // we've swapped out ids[0] and ids[1], so the old ids[0] would be null after repayment, then the swap happens
        assertEq(line.ids(2), id3);
        assertEq(line.ids(3), id2);

        // close the next available line
        line.depositAndClose();

        assertEq(line.ids(0), id3);
        assertEq(line.ids(1), bytes32(0)); 
        assertEq(line.ids(2), bytes32(0));// we've swapped out ids[0] and ids[2], so the old ids[0] would be null after repayment, then the swap happens
        assertEq(line.ids(3), id2);

        vm.stopPrank();
    }




    /*//////////////////////////////////
                U T I L S
    //////////////////////////////////*/

    function _mintAndApprove() internal {
        deal(lender, mintAmount);

        supportedToken1.mint(borrower, mintAmount);
        supportedToken1.mint(lender, mintAmount);
        supportedToken2.mint(borrower, mintAmount);
        supportedToken2.mint(lender, mintAmount);
        unsupportedToken.mint(borrower, mintAmount);
        unsupportedToken.mint(lender, mintAmount);

        vm.startPrank(borrower);
        supportedToken1.approve(address(line), MAX_INT);
        supportedToken2.approve(address(line), MAX_INT);
        unsupportedToken.approve(address(line), MAX_INT);
        vm.stopPrank();

        vm.startPrank(lender);
        supportedToken1.approve(address(line), MAX_INT);
        supportedToken2.approve(address(line), MAX_INT);
        unsupportedToken.approve(address(line), MAX_INT);
        vm.stopPrank();
    }

    function _addCredit(address token, uint256 amount) public {
        vm.startPrank(borrower);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
        vm.startPrank(lender);
        vm.expectEmit(false, true, true, false);
        emit Events.SetRates(bytes32(0), dRate, fRate);
        line.addCredit(dRate, fRate, amount, token, lender);
        vm.stopPrank();
    }

        function setupQueueTest(uint256 amount)
        internal
        returns (address[] memory)
    {
        address[] memory tokens = new address[](amount);
        // generate token for simulating different repayment flows
        for (uint256 i = 0; i < amount; i++) {
            RevenueToken token = new RevenueToken();
            tokens[i] = address(token);

            token.mint(lender, mintAmount);
            token.mint(borrower, mintAmount);

            hoax(lender);
            token.approve(address(line), mintAmount);
            hoax(borrower);
            token.approve(address(line), mintAmount);

            oracle.changePrice(address(token), 1 ether);

            // add collateral for each token so we can borrow it during tests
        }

        return tokens;
    }

    function _assignQueueLabels() internal {
        
        string[15] memory labels = [' id','id2','id3','id4','id5','id6','id7','id8','id9','id10','id11','id12','id13', "id14", "id15"];
        idLabels[bytes32(0)] = " * ";

        (,uint256 numPositions) = line.counts();
        for (uint i; i < numPositions; ++i) {
            idLabels[line.ids(i)] = labels[i];
        }
    }

    function _formatLoggedArrOfIds(string memory msg) internal {
        string memory arr = "[ ";
        (,uint256 numPositions) = line.counts();
        for (uint i; i < numPositions; ++i) {
            arr = string(abi.encodePacked(arr, idLabels[line.ids(i)], " "));
        }
        arr = string(abi.encodePacked(arr, "]", " <=== ", msg));
        console.log(arr);
    }
}