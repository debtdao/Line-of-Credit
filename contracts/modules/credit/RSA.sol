// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";

import {ISpigot} from "../../interfaces/ISpigot.sol";
import { MutualConsent } from "../../utils/MutualConsent.sol";

// TODO import GPv2 data types

struct Order {

    address sellToken; // any token earned as revenue
    address buyToken; // always creditToken
    uint256 sellAmount; // always defined
    uint256 buyAmount; // can be open ended or use pre-agreed floorPrice
    address receiver; // always address(this)
    uint256 validTo; // timestamp for deadline of order
    bytes appData; // not used onchain but could be used offchain
    uint256 feeAmount; // always 0
    string[4] kind; // always 'sell' incase we do ever charge fees we take from borrower revenue streams not creditors
    bool partiallyFillable; // always true
    
    string[5] sellTokenBalance; // always 'erc20' to use native ERC20 balances not BAL/GNO protocol balances
    string[5] buyTokenBalance; // always 'erc20' to use native ERC20 balances not BAL/GNO protocol balances

    string[7] signingScheme; // always 'eip1271'
    address from; // always addressI(this)
}

/**
* @title Revenue Share Agreemnt
* @author Kiba Gateaux
* @notice Allows a borrower with revenue streams collateralized in a Spigot to  borrow against them from a single lender
* Lender is guaranteed a specific return but payments are variable based on revenue and % split between borrower and lender.
* Claims on revenue are tokenized as ERC20 at 1:1 redemption rate for the credit token being lent/repaid.
* All claim tokens are minted immediately to the lender and must be burnt to claim credit tokens. 
* Borrower or Lender can trade any revenue token at any time to the token owed to lender using CowSwap Smart Orders
* Borrower and Lender can mutually agree to set a minimum price for specific revenue tokens to prevent cowswap from executing non-optimal trades.
*
*/
contract RevenueShareAgreement is ERC20, MutualConsent {
    using ECDSA for bytes32;
    using SafeERC20 for ERC20;
    
    // ERC-1271 signature
    uint256 private constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    address private constant COWSWAP_SETTLEMENT_ADDRESS = address(0xdead);
    bytes4 private constant ERC_1271_MAGIC_VALUE = bytes4(0);
    bytes32 private constant COW_ORDER_HASH = keccak256("Order(string name,string version,uint256 chainId,address verifyingContract)");
    uint8 private constant MAX_REVENUE_SPLIT = 100;

    ISpigot public spigot;
    address public lender;
    address public borrower;
    address public creditToken;
    uint8 public lenderRevenueSplit;

    // denomainated in creditToken
    uint256 public initialPrincipal;
    uint256 public totalOwed;
    uint256 public currentDeposits; // total repaid from revenue - total withdrawn by

    // data required to confirm order data from solver/settler
    mapping(bytes32 => uint256) public orders;

    error InvalidPaymentSetting();
    error InvalidRevenueSplit();
    error CantSweepWhileInDebt();
    error DepositsFull();
    error InvalidTradeId();
    error NotBorrower();
    error NotLender();

    constructor(
        address _spigot,
        address _borrower,
        address _creditToken,
        uint8 _revenueSplit,
        uint256 _initialPrincipal,
        uint256 _totalOwed,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 18) {
        spigot = ISpigot(_spigot);
        borrower = _borrower;

        if(_initialPrincipal > _totalOwed) {
            revert InvalidPaymentSetting();
        }

        if(_revenueSplit > MAX_REVENUE_SPLIT) {
            revert InvalidRevenueSplit();
        }

        lenderRevenueSplit = _revenueSplit;
        creditToken = _creditToken;
        initialPrincipal = _initialPrincipal;
        totalOwed = _totalOwed;
    }


    /**
    * @notice Lets lenders deposit Borrower's requested loan amount into RSA and receive back redeemable shares of revenue stream
    * @dev callable by anyone if offer not accepted yet
    */
    function deposit() external returns(bool) {
        if(lender != address(0)) {
            revert DepositsFull();
        }
        // store who accepted borrower's offer. only 1 lender
        lender = msg.sender;
        // issue RSA token to lender to redeem later
        _mint(msg.sender, totalOwed);
        // extend credit to borrower
        ERC20(creditToken).transferFrom(msg.sender, borrower, initialPrincipal);

        return true;
    }

    /**
    * @notice Lets Lender redeem their original tokens.
    * @param _amount - amount of RSA tokens to redeem @ 1:1 ratio for creditToken
    * @dev callable by anyone if offer not accepted yet
    */
    function claim(uint256 _amount) external returns(bool) {
        _burn(msg.sender, _amount); // anyone can redeem not restricted to original lender
        ERC20(creditToken).transfer(msg.sender, _amount);
        return true;
    }


    /**
    * @notice Lets Borrower redeem any excess revenue not needed to repay lenders.
    *         We do not track any tokens held in this contract so yeet entire balance to sweeper.
    * @dev    Only callable if RSA not initiated yet or after RSA is fully repaid.
    * @param _token - amount of RSA tokens to redeem @ 1:1 ratio for creditToken
    * @param _to    - who to sweep tokens to
    */
    function sweep(address _token, address _to) external returns(bool) {
        // cannot withdraw spigot until the RSA has been repaid
        if(lender != address(0) && totalOwed != 0) {
            revert CantSweepWhileInDebt();
        }
        if(msg.sender != borrower) {
            revert NotBorrower();
        }

        ERC20(_token).transfer(_to, ERC20(_token).balanceOf(address(this)));
        
        return true;
    }   

    /**
    * @notice Lets Borrower reclaim their Spigot after paying off all their debt.
    * @dev    Only callable if RSA not initiated yet or after RSA is fully repaid.
    * @param _to    - who to give ownerhsip of Spigot to
    */
    function releaseSpigot(address _to) external returns(bool) {
        if(msg.sender != borrower) {
            revert NotBorrower();
        }

        // cannot withdraw spigot until the RSA has been repaid
        if(lender != address(0) && totalOwed != 0) {
            revert CantSweepWhileInDebt();
        }

        ISpigot(spigot).updateOwner(_to);
        
        return true;
    }   

    function finalizeTrade(bytes32 tradeHash) external {
        // not sure if we need this. generated by AI. Read cowswap docs
        // at min need a "push payment" type thing to read new credit Tokens in our contract thats diff from currentDeposits

        require(msg.sender == lender || msg.sender == borrower, "Caller must be lender");

        // need to do this in finalized trade so need to save trade hash here with token, amount, preBalance, and minPrice (incase changed later or in order to change later and resubmit)
        // any new credit tokens added to our balance ssince we last updated
        uint256 boughtAmount = ERC20(creditToken).balanceOf(address(this)) - currentDeposits;
        require(boughtAmount != 0, "No payment received");

        currentDeposits += currentDeposits;
        totalOwed -= currentDeposits;

        emit TradeFinalized(tradeHash);
    }

    function claimRev(address _token) external returns(uint256) {
        return spigot.claimOwnerTokens(_token);
    }

    /**
    * @notice Gives Borrower AND Lender the ability to trade any revenue token into the token owed by lenders
    * @param _revenueToken - The token claimed from Spigot to sell for creditToken
    * @param _sellAmount - How many revenue tokens to sell. MUST be > 0
    * @param _minBuyAmount - Minimum amount of creditToken to buy during trade. Can be 0
    * @param _deadline - block timestamp that trade is valid until
    */
    function initiateTrade(
        address _revenueToken,
        uint256 _sellAmount,
        uint256 _minBuyAmount,
        uint256 _deadline
    ) external returns(bytes32) {
        require(totalOwed !=  0, "Trade not required");
        require(_revenueToken !=  creditToken, "Cant sell token being bought");
        require(_sellAmount !=  0, "Invalid trade amount");
        require(_deadline >= block.timestamp, "Trade _deadline has passed");
        require(msg.sender == lender || msg.sender == borrower, "Caller must be stakeholder");

        // increase so multiple revenue streams in same token dont override each other
        // we always sell all revenue tokens
        ERC20(_revenueToken).approve(COWSWAP_SETTLEMENT_ADDRESS, MAX_UINT);

        bytes32 tradeHash = _constructOrder(_revenueToken, _sellAmount, _minBuyAmount, _deadline);
        orders[tradeHash] = 1;
        emit TradeInitiated(tradeHash, _sellAmount, _minBuyAmount, _deadline);

        return tradeHash;
    }

    function isValidSignature(bytes32 _tradeHash, bytes calldata _signature) external view returns (bytes4) {
        if (orders[_tradeHash] == 0) {
            revert InvalidTradeId();
        }

        // can do add any arbitrry data to appData in Order to verify who submitted, zk proof price is above min, etc.
        // bytes32 tradeHash = keccak256(
        //     abi.encodePacked(address(this), tradeAmount, minPrice, deadline)
        // ).toEthSignedMessageHash();
        // require(
        //     ECDSA.recover(tradeHash, _signature) == lender,
        //     "Signature must be from lender"
        // );
        // orders[tradeHash] = Order({ });

        return ERC_1271_MAGIC_VALUE;
    }

    /**
    * @notice Allows lender to whitelist specific functions for Spigot operator to call for product maintainence
    * @param _whitelistedFunc - the function to whitelist across revenue contracts
    * @param _allowed -if function can be called by operator or not
    * @return bool - if update was successful
    */
    function updateWhitelist(bytes4 _whitelistedFunc, bool _allowed) external returns(bool) {
        if(msg.sender != lender) {
            revert NotLender();
        }

        spigot.updateWhitelistedFunction(_whitelistedFunc, _allowed);
        
        return true;
    }

    /**
    * @notice Allowsborrower to add more revenue streams to their RSA to increase repayment speed
    * @param revenueContract - the contract to add revenue for
    * @param claimFunc - Function to call on revenue contract tto claim revenue into the Spigot.
    * @param transferFunc - Function on revenue contract to call to transfer ownership. MUST only take 1 parameter that is the new owner
    * @return bool - if update was successful
    *
    */
    function addSpigot(address revenueContract, bytes4 claimFunc, bytes4 transferFunc) external returns(bool) {
        if(msg.sender != borrower) {
            revert NotBorrower();
        }

        spigot.addSpigot(revenueContract, ISpigot.Setting(lenderRevenueSplit, claimFunc, transferFunc));
        
        return true;
    }

    /**
    * @notice Allows updating any revenue stream in Spigot to the agreed split.
    * Useful incase spigot configured before put into RSA 
    * @param revenueContract - the contract to reset
    * @return bool - if update was successful
     */
    function resetRevenueSplit(address revenueContract) external returns(bool) {
        spigot.updateOwnerSplit(revenueContract, lenderRevenueSplit);
        return true;
    }

    /**
    * @notice   - Generates GnosisProtcool v2 structured trade order data with ERC712 signature.
                This order will be signed by this RSA contract to authorize sales of revenue tokens
    * @param _revenueToken - the token being sold
    * @param _sellAmount -  amount of _revenueToken to sell
    * @param _buyAmount - amount of creditToken to buy
    * @param _deadline - until when ordershould be valid
    * @return hash - trade hsh used to verify that the order is valid and from this contract
     */

    function _constructOrder(address _revenueToken, uint256 _sellAmount, uint256 _buyAmount, uint256 _deadline) internal view returns (bytes32) {
        bytes32 tradeHash = keccak256(abi.encodePacked(
            "\\x19\\x01",
            DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                COW_ORDER_HASH,
                _revenueToken,  // sellToken
                creditToken,    // buyToken
                _sellAmount,    // sellAmount
                _buyAmount,     // buyAmount
                address(this),  // receiver
                _deadline,      // validTo
                "",             // appData
                0,              // feeAmount
                'sell',         // kind
                true,           // partiallyFillable
                'erc20',        // sellTokenBalance
                'erc20',        // buyTokenBalance
                'eip1271',      // signingScheme
                address(this)   // from
            ))
        ));

        return tradeHash;
    }

    event TradeInitiated(
        bytes32 indexed tradeHash,
        uint256 indexed sellAmount,
        uint256 indexed minBuyAmount,
        uint256 deadline
    );
    event TradeFinalized(bytes32 indexed tradeHash);
}
