// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";

import {ISpigot} from "../../interfaces/ISpigot.sol";
// import {IRevenueShareAgreement} from "../../interfaces/IRevenueShareAgreement.sol";
import {GPv2Order} from "../../utils/GPv2Order.sol";

/**
* @title Revenue Share Agreemnt
* @author Kiba Gateaux
* @notice Allows a borrower with revenue streams collateralized in a Spigot to borrow against them from a single lender
* Lender is guaranteed a specific return but payments are variable based on revenue and % split between borrower and lender.
* Claims on revenue are tokenized as ERC20 at 1:1 redemption rate for the credit token being lent/repaid.
* All claim tokens are minted immediately to the lender and must be burnt to claim credit tokens. 
* Borrower or Lender can trade any revenue token at any time to the token owed to lender using CowSwap Smart Orders
* @dev - reference  https://github.com/charlesndalton/milkman/blob/main/contracts/Milkman.sol
*/
contract RevenueShareAgreement is ERC20 {
    using ECDSA for bytes32;
    using GPv2Order for GPv2Order.Data;
    
    // ERC-1271 signature
    uint256 internal constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    /// @dev The contract that settles all trades. Must approve sell tokens to this address.
    address internal constant COWSWAP_SETTLEMENT_ADDRESS = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    /// @dev The settlement contract's EIP-712 domain separator. Milkman uses this to verify that a provided UID matches provided order parameters.
    bytes32 internal constant COW_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    bytes4 internal constant ERC_1271_MAGIC_VALUE =  0x1626ba7e;
    bytes4 internal constant ERC_1271_NON_MAGIC_VALUE = 0xffffffff;
    uint8 internal constant MAX_REVENUE_SPLIT = 100;

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
    error InvalidTradeData();
    error ExceedClaimableTokens(uint256 claimable);
    error NotBorrower();
    error AlreadyInitialized();
    error InvalidSpigotAddress();
    error InvalidBorrowerAddress();
    error InvalidTradeDomain();
    error InvalidTradeDeadline();
    error InvalidTradeTokens();
    error InvalidTradeBalanceDestination();
    error MustBeSellOrder();
    error NotLender();

    constructor() ERC20("Debt DAO Revenue Share Agreement", "RSA", 18) {}

    function initialize(
        address _spigot,
        address _borrower,
        address _creditToken,
        uint8 _revenueSplit,
        uint256 _initialPrincipal,
        uint256 _totalOwed,
        string memory _name,
        string memory _symbol
    ) external {
        if(borrower != address(0)) {
            revert AlreadyInitialized();
        }

        if(_spigot == address(0)) {
            revert InvalidSpigotAddress();
        }
        if(_borrower == address(0)) {
            revert InvalidBorrowerAddress();
        }

        if(_initialPrincipal > _totalOwed) {
            revert InvalidPaymentSetting();
        }

        if(_revenueSplit > MAX_REVENUE_SPLIT) {
            revert InvalidRevenueSplit();
        }
        // ERC20 vars
        name = _name;
        symbol = _symbol;
        // RSA stakeholders
        borrower = _borrower;
        spigot = ISpigot(_spigot);
        // RSA finanical terms
        totalOwed = _totalOwed;
        creditToken = _creditToken;
        lenderRevenueSplit = _revenueSplit;
        initialPrincipal = _initialPrincipal;
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

        emit Deposit(lender);
        return true;
    }

    /**
    * @notice Lets Lender redeem their original tokens.
    * @param _amount - amount of RSA tokens to redeem @ 1:1 ratio for creditToken
    * @param _to - who to send claimed creditTokens to
    * @dev callable by anyone if offer not accepted yet
    */
    function redeem(uint256 _amount, address _to) external returns(bool) {
        // _burn only checks their RSA token balance and
        // ERC20.transfer may move tokens we havent accounted for yet
        if(_amount > currentDeposits) {
            revert ExceedClaimableTokens(currentDeposits);
        }
        
        // anyone can redeem not restricted to original lender
        currentDeposits -= _amount;
        _burn(msg.sender, _amount);

        ERC20(creditToken).transfer(_to, _amount);
        
        emit Redeem(_to, msg.sender, _amount);
        return true;
    }

    /**
    * @notice Pulls all tokens allocated to RSA from Spigot. Hold for later use in trades
    * @param _token - token we want to claim and eventually sell
    * @dev callable by anyone. no state change, MEV, exploit potential
    */
    function claimRev(address _token) external returns(uint256 claimed) {
        claimed = spigot.claimOwnerTokens(_token);
        if(_token == creditToken) {
            // if revenue in creditToken, we can immediately paydown debt
            _updateDebtBalance();
        }
    }

    /**
    * @notice Accounts for all credit tokens bought and updates debt and deposit balances
    * @dev callable by anyone.
    */
    function updateDebtBalance() external returns(uint256 claimed) {
        return _updateDebtBalance();
    }

    /**
    * @notice Lets Borrower redeem any excess revenue not needed to repay lenders.
    *         We do not track any tokens held in this contract so yeet entire balance to sweeper.
    * @dev    Only callable if RSA not initiated yet or after RSA is fully repaid.
    * @param _token - amount of RSA tokens to redeem @ 1:1 ratio for creditToken
    * @param _to    - who to sweep tokens to
    */
    function sweep(address _token, address _to) external returns(bool) {
        // cannot Redeem spigot until the RSA has been repaid
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

        // cannot Redeem spigot until the RSA has been repaid
        if(lender != address(0) && totalOwed != 0) {
            revert CantSweepWhileInDebt();
        }

        ISpigot(spigot).updateOwner(_to);
        
        return true;
    }

    /**
    * @notice Gives Borrower AND Lender the ability to trade any revenue token into the token owed by lenders
    * @param _revenueToken - The token claimed from Spigot to sell for creditToken
    * @param _sellAmount - How many revenue tokens to sell. MUST be > 0
    * @param _minBuyAmount - Minimum amount of creditToken to buy during trade. Can be 0
    * @param _deadline - block timestamp that trade is valid until
    */
    function initiateOrder(
        address _revenueToken,
        uint256 _sellAmount,
        uint256 _minBuyAmount,
        uint256 _deadline
    ) external returns(bytes32 tradeHash) {
        require(totalOwed !=  0, "Trade not required");
        require(_revenueToken !=  creditToken, "Cant sell token being bought");
        require(_sellAmount !=  0, "Invalid trade amount");
        require(_deadline >= block.timestamp, "Trade _deadline has passed");
        require(msg.sender == lender || msg.sender == borrower, "Caller must be stakeholder");

        // increase so multiple revenue streams in same token dont override each other
        // we always sell all revenue tokens
        ERC20(_revenueToken).approve(COWSWAP_SETTLEMENT_ADDRESS, MAX_UINT);

        tradeHash = _encodeOrder(_revenueToken, _sellAmount, _minBuyAmount, _deadline);
        orders[tradeHash] = 1;
        emit TradeInitiated(tradeHash, _sellAmount, _minBuyAmount, _deadline);
    }

    /*
    function finalizeOrder(
        bytes calldata _completedOrder
    ) external returns(bool) {
        // bc of offchain solver and execution we dont know actual price we execute out
        // would be nice to submit somekinf of proof to say how many tokens were bought in a sepcific trade
        // would make the orders mapping actually useful and can do TradeRevenue event like in LineOfCredit
        return false;
    }
    */

   
    function isValidSignature(bytes32 _tradeHash, bytes calldata _encodedOrder) external view returns (bytes4) {
        GPv2Order.Data memory _order = abi.decode(_encodedOrder, (GPv2Order.Data));
        
        /* 
        decide if we want dynamic price checker or user puts minOut+deadline in order creation
        (
            GPv2Order.Data memory _order,
            address _orderCreator,
            address _priceChecker,
            bytes memory _priceCheckerData
        ) = _decodeOrder(_encodedOrder);
        */

        bytes32 _calculatedSwapHash = _encodeOrder(_order.sellToken, _order.sellAmount, _order.buyAmount, _order.validTo);

        if(_calculatedSwapHash != _tradeHash) {
             // same as checking `orders[_calculatedSwapHash] == 0` but cheaper
            revert InvalidTradeData();
            // might need to return ERC_1271_NON_MAGIC_VALUE here. Not sure what EIP says
        }

        if (orders[_calculatedSwapHash] == 0) {
            // must've registered trade first in ordre to validate it
            revert InvalidTradeId();
        }

        if(_order.hash(COW_DOMAIN_SEPARATOR) != _tradeHash) {
            revert InvalidTradeDomain();
        } 

        if(_order.kind != GPv2Order.KIND_SELL) {
            revert MustBeSellOrder();
        }

        // ensure we have sufficient time to execute trade
        if(_order.validTo >= block.timestamp + 10 minutes) {
            revert InvalidTradeDeadline();
        }

        // ensure we are buying the right token. 
        // Cant sell creditToken to prevent griefing
        if(_order.sellToken == creditToken || _order.buyToken != creditToken) {
            revert InvalidTradeTokens();
        }

        // pretty sure we dont care about fill status
        // if(_order.partiallyFillable) { revert MustFillOrder(); }

        // ensure tokens are sent directly to contracts and not stored in Balancer vault.
        if(
            _order.sellTokenBalance == GPv2Order.BALANCE_ERC20 && 
            _order.buyTokenBalance == GPv2Order.BALANCE_ERC20
        ) {
            revert InvalidTradeBalanceDestination();
        }

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
    function setRevenueSplit(address revenueContract) external returns(bool) {
        spigot.updateOwnerSplit(revenueContract, lenderRevenueSplit);
        return true;
    }

    function _updateDebtBalance() internal returns(uint256) {
        uint256 newPayments = ERC20(creditToken).balanceOf(address(this)) - currentDeposits;
        currentDeposits += newPayments;
        totalOwed -= newPayments;
        return newPayments;
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
    function _encodeOrder(address _revenueToken, uint256 _sellAmount, uint256 _buyAmount, uint256 _deadline) internal view returns (bytes32) {
        bytes32 tradeHash = keccak256(abi.encodePacked(
            "\\x19\\x01",
            DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                GPv2Order.TYPE_HASH,
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

    // decide if we want dynamic price checker or user puts minOut+deadline in order creation
    // function _decodeOrder(bytes calldata _encodedOrder)
    //     internal
    //     pure
    //     returns (
    //         GPv2Order.Data memory _order,
    //         address _orderCreator,
    //         address _priceChecker,
    //         bytes memory _priceCheckerData
    //     )
    // {
    //     (_order, _orderCreator, _priceChecker, _priceCheckerData) = abi.decode(
    //         _encodedOrder,
    //         (GPv2Order.Data, address, address, bytes)
    //     );
    // }

    event TradeInitiated(
        bytes32 indexed tradeHash,
        uint256 indexed sellAmount,
        uint256 indexed minBuyAmount,
        uint256 deadline
    );

    event Redeem(
        address indexed receiver,
        address indexed owner,
        uint256 amount
    );


    event Deposit(address indexed lender);
    event TradeFinalized(bytes32 indexed tradeHash);
}
