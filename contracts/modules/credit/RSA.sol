// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";

import {ISpigot} from "../../interfaces/ISpigot.sol";
import { MutualConsent } from "../../utils/MutualConsent.sol";

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
    bytes32 signature; // actual signature for the order
    address from; // always addressI(this)
}

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
    uint256 public priceDecimals; // denominated in creditToken. not to be confused with RSA token decimals

    /// @notice  revenue token -> 8 decimal price in credit tokens.
    /// e.g. 2e8 == means we must sell <= 0.5 revenue tokens to buy 1 credit token
    mapping(address => uint16) public floorPrices;
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
        priceDecimals = 10 ** ERC20(_creditToken).decimals();

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

    function deposit() external returns(bool) {
        if(lender != address(0)) {
            revert DepositsFull();
        }

        lender = msg.sender;
        _mint(msg.sender, totalOwed);

        ERC20(creditToken).transferFrom(msg.sender, borrower, initialPrincipal);

        return true;
    }

    function claim(uint256 _amount) external returns(bool) {
        _burn(msg.sender, _amount); // anyone can redeem not restricted to original lender
        ERC20(creditToken).transfer(msg.sender, _amount);
        return true;
    }

    function sweep(address _token) external returns(bool) {
        if(msg.sender != borrower) {
            revert NotBorrower();
        }
        if(totalOwed != 0) {
            revert CantSweepWhileInDebt();
        }

        ERC20(_token).transfer(msg.sender, ERC20(_token).balanceOf(address(this)));
        
        return true;
    }   

    function releaseSpigot(address _to) external returns(bool) {
        if(msg.sender != borrower) {
            revert NotBorrower();
        }
        
        // can withdraw spigot until the loan has been funded
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

    function initiateTrade(
        address revenueToken,
        uint256 tradeAmount,
        uint256 deadline,
        bytes calldata signature
    ) external returns(bytes32) {
        require(revenueToken !=  creditToken, "Cant sell token being bought");
        require(tradeAmount !=  0, "Invalid trade amount");
        require(deadline >= block.timestamp, "Trade deadline has passed");
        require(msg.sender == lender || msg.sender == borrower, "Caller must be stakeholder");

        uint256 balanceBefore = ERC20(creditToken).balanceOf(address(this));
        
        uint256 minPrice = floorPrices[revenueToken];

        // increase so multiple revenue streams in same token dont override each other
        // we always sell all revenue tokens
        ERC20(revenueToken).approve(COWSWAP_SETTLEMENT_ADDRESS, MAX_UINT);

        bytes32 tradeHash = _constructOrder(revenueToken, tradeAmount, deadline);
        orders[tradeHash] = 1;
        emit TradeInitiated(tradeHash, tradeAmount, minPrice, deadline);

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
        //     ECDSA.recover(tradeHash, signature) == lender,
        //     "Signature must be from lender"
        // );
        // orders[tradeHash] = Order({ });

        return ERC_1271_MAGIC_VALUE;
    }

    function setFloorPrice(address _revenueToken, uint16 _price) mutualConsent(borrower, lender) external returns(bool) {
        floorPrices[_revenueToken] = _price;
        return true;
    }

    /**
    * @notice Allows lender to whitelist specific functions for Spigot operator to call for product maintainence
    * @param _whitelistedFunc - the function to whitelist across revenue contracts
    * @param _allowed -if function can be called by operator or not
    * @return if update was successful
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
    * @return if update was successful
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
    * @return if update was successful
     */
    function resetRevenueSplit(address revenueContract) external returns(bool) {
        spigot.updateOwnerSplit(revenueContract, lenderRevenueSplit);
        return true;
    }

    function _constructOrder(address _revenueToken, uint256 _sellAmount, uint256 _deadline) internal view returns (bytes32) {
        bytes32 tradeHash = keccak256(abi.encodePacked(
            "\\x19\\x01",
            DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                COW_ORDER_HASH,
                _revenueToken,  // sellToken
                creditToken,    // buyToken
                _sellAmount,    // sellAmount
                0,              // buyAmount
                address(this),  // receiver
                _deadline,      // validTo
                "",             // appData
                0,              // feeAmount
                'sell',         // kind
                true,           // partiallyFillable
                'erc20',        // sellTokenBalance
                'erc20',        // buyTokenBalance
                'eip1271',      // signingScheme
                "",             // signature
                address(this)   // from
            ))
        ));

        // return Order({
        //     sellToken: _revenueToken, // any token earned as revenue
        //     buyToken: creditToken, // always creditToken
        //     sellAmount: _sellAmount, // always defined
        //     buyAmount: 0, // can be open ended or use pre-agreed floorPrice
        //     receiver: address(this), // always address(this)
        //     validTo: _deadline, // timestamp for deadline of order
        //     appData: "", // not used onchain but could be used offchain
        //     feeAmount: 0, // always 0
        //     kind: 'sell', // always 'sell' incase we do ever charge fees we take from borrower revenue streams not creditors
        //     partiallyFillable: true, // always true
            
        //     sellTokenBalance: 'erc20', // always 'erc20' to use native ERC20 balances not BAL/GNO protocol balances
        //     buyTokenBalance: 'erc20', // always 'erc20' to use native ERC20 balances not BAL/GNO protocol balances

        //     signingScheme: 'eip1271',  // always 'eip1271'
        //     signature: "", // actual signature for the order
        //     from: address(this) // always addressI(this)
        // });

        return tradeHash;
    }

    function _normalizePrice(address quoteToken, uint256 baseAmount, uint256 quoteAmount) internal view returns (uint256)  {
        // offset division by base decimals and then add priceDecimals
        return (quoteAmount * priceDecimals * priceDecimals) / (baseAmount * ERC20(quoteToken).decimals());
    }

    event TradeInitiated(
        bytes32 indexed tradeHash,
        uint256 indexed tradeAmount,
        uint256 indexed minPrice,
        uint256 deadline
    );
    event TradeFinalized(bytes32 indexed tradeHash);
}
