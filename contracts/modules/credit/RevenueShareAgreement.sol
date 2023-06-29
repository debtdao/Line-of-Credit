// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {GPv2Order} from "../../utils/GPv2Order.sol";

import {ISpigot} from "../../interfaces/ISpigot.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {IRevenueShareAgreement} from "../../interfaces/IRevenueShareAgreement.sol";
import { getWrapper, UnsupportedNetwork } from "../../utils/Multichain.sol";

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
contract RevenueShareAgreement is IRevenueShareAgreement, ERC20 {
    using GPv2Order for GPv2Order.Data;
    /// @notice The contract that settles all trades. Must approve sell tokens to this address.
    /// @dev Same address acorss all chains
    address internal constant COWSWAP_SETTLEMENT_ADDRESS = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    /// @notice The settlement contract's EIP-712 domain separator. Milkman uses this to verify that a provided UID matches provided order parameters.
    /// @dev Same acorss all chains because settlement address is the same
    bytes32 internal constant COWSWAP_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    bytes4 internal constant ERC_1271_MAGIC_VALUE =  0x1626ba7e;
    bytes4 internal constant ERC_1271_NON_MAGIC_VALUE = 0xffffffff;
    uint8 internal constant MAX_REVENUE_SPLIT = 100;
    uint256 internal constant MAX_TRADE_DEADLINE = 1 days;
    IWETH internal WETH;

    ISpigot public spigot;
    address public lender;
    address public borrower;
    address public creditToken;
    uint8 public lenderRevenueSplit;

    // denominated in creditToken
    uint256 public initialPrincipal;
    uint256 public totalOwed;
    uint256 public claimableAmount; // total repaid from revenue - total withdrawn by

    mapping(bytes32 => uint32) public orders; // deadline for order`


    constructor() ERC20("Debt DAO Revenue Share Agreement", "RSA", 18) {}

    function initialize(
        address _borrower,
        address _spigot,
        address _creditToken,
        uint8 _revenueSplit,
        uint256 _initialPrincipal,
        uint256 _totalOwed,
        string memory _name,
        string memory _symbol
    ) external {
        if(borrower != address(0))              revert AlreadyInitialized();
        // prevent re-initialization
        if(_borrower == address(0))             revert InvalidBorrowerAddress();

        if(_spigot == address(0))               revert InvalidSpigotAddress();

        if(_initialPrincipal > _totalOwed)      revert InvalidPaymentSetting();

        if(_revenueSplit > MAX_REVENUE_SPLIT)   revert InvalidRevenueSplit();

        // ERC20 vars
        name = _name;
        symbol = _symbol;

        // RSA stakeholders
        borrower = _borrower;
        spigot = ISpigot(_spigot);

        // RSA financial terms
        totalOwed = _totalOwed;
        creditToken = _creditToken;
        lenderRevenueSplit = _revenueSplit;
        initialPrincipal = _initialPrincipal;
        _setWrapperForNetwork();
    }

    /**
    * @notice Lets lenders deposit Borrower's requested loan amount into RSA and receive back redeemable shares of revenue stream
    * @dev callable by anyone if offer not accepted yet
    */
    function deposit(address _receiver) external returns(bool) {
        if(lender != address(0)) {
            revert DepositsFull();
        }

        // store who accepted borrower's offer. only 1 lender per RSA
        lender = msg.sender;
        // issue RSA token to lender to redeem later
        _mint(_receiver, totalOwed);
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
    function redeem(address _owner, address _to, uint256 _amount) external returns(bool) {
        if(_amount > claimableAmount) {
            // _burn only checks their RSA token balance so
            // creditToken.transfer may move tokens we havent
            // properly accountted for as revenue yet.

            // If creditToken.balanceOf(this) > _amount but redeem() fails then call
            // repay() to account for the missing tokens.
            revert ExceedClaimableTokens(claimableAmount);
        }
        
        // check that caller has approval on _owner tokens
        if(msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender]; // Saves gas for limited approvals.
            if (allowed != type(uint256).max) {
                if(_amount > allowed) revert InsufficientAllowance();
                else allowance[_owner][msg.sender] -= _amount;
            }
        }
        
        // anyone can redeem not restricted to original lender
        claimableAmount -= _amount;
        _burn(_owner, _amount);

        ERC20(creditToken).transfer(_to, _amount);
        
        emit Redeem(_to, _owner, msg.sender, _amount);
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
            // immediately paydown debt w/o trading if possible 
            _repay();
        }
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
        uint32 _deadline
    ) external returns(bytes32 tradeHash) {
        require(lender != address(0), "agreement unitinitiated");
        require(msg.sender == lender || msg.sender == borrower, "Caller must be stakeholder");
        _assertOrderParams(_revenueToken, _sellAmount, _minBuyAmount, _deadline);
        // not sure if we need to check balance, order would just fail.
        // might be an issue with approving an invalid order that could be exploited later
        // require(_sellAmount >= ERC20(_revenueToken).balanceOf(address(this)), "No tokens to trade");

        // call max so multiple orders/revenue streams with same token dont override each other
        // we always specify a specific amount of revenue tokens to sell but not all tokens support increaseAllowance
        ERC20(_revenueToken).approve(COWSWAP_SETTLEMENT_ADDRESS, type(uint256).max);

        tradeHash = generateOrder(
            _revenueToken,
            _sellAmount,
            _minBuyAmount,
            _deadline
        ).hash(COWSWAP_DOMAIN_SEPARATOR);
        // hash order with settlement contract as EIP-712 verifier
        // Then settlement calls back to our isValidSignature to verify trade

        orders[tradeHash] = block.timestamp + MAX_TRADE_DEADLINE;
        emit OrderInitiated(creditToken, _revenueToken, tradeHash, _sellAmount, _minBuyAmount, _deadline);
    }

    /**
    * @notice Wraps ETH to WETH (or other respective asset) because CoWswap only supports ERC20 tokens.
    *         This is easier than using their ETH flow.
    *         We dont allow native ETH as creditToken so any ETH is revenue and should be wrapped.
    * @dev callable by anyone. no state change, MEV, exploit potential
    * @return amount - amount of ETH wrapped 
    */
    function wrap() external returns(uint256 amount) {
        uint256 initialBalance = WETH.balanceOf(address(this));
        amount = address(this).balance;

        WETH.deposit{value: amount}();
        
        uint256 postBalance = WETH.balanceOf(address(this));
        if(postBalance - initialBalance != amount) {
            revert InvalidWETHDeposit();
        }
    }

    /**
    * @notice Accounts for all credit tokens bought and updates debt and deposit balances
    * @dev callable by anyone.
    */
    function repay() external returns(uint256 claimed) {
        return _repay();
    }

    /**
    * @notice Lets Borrower redeem any excess revenue not needed to repay lenders.
    *         We assume any token in this contract is a revenue token and is collateral
    *         so only callable if no lender deposits yet or after RSA is fully repaid.
    *         Full token balance is swept to `_to`.
    * @dev   If you need to sweep raw ETH call wrapETH() first.
    * @param _token - amount of RSA tokens to redeem @ 1:1 ratio for creditToken
    * @param _to    - who to sweep tokens to
    */
    function sweep(address _token, address _to) external returns(bool) {
        if(msg.sender != borrower) {
            revert NotBorrower();
        }

        if(lender != address(0) && totalOwed != 0) {
            revert CantSweepWhileInDebt();
        }

        uint256 balance = ERC20(_token).balanceOf(address(this));
        if(_token == creditToken) {
            // If all debt is repaid but lenders still havent claimed underlying
            // keep enough underlying for redemptions
            // NOTE: totalSupply == 0 until deposit() called
            ERC20(_token).transfer(_to, balance - totalSupply);
        } else {
            ERC20(_token).transfer(_to, balance);
        }

        
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

        // can reclaim if no lender has deposited yet, else
        // cannot Redeem spigot until the RSA has been repaid
        if(lender != address(0) && totalOwed != 0) {
            revert CantSweepWhileInDebt();
        }

        ISpigot(spigot).updateOwner(_to);
        
        return true;
    }
   
    function isValidSignature(bytes32 _tradeHash, bytes calldata _encodedOrder) external view returns (bytes4) {
        GPv2Order.Data memory _order = abi.decode(_encodedOrder, (GPv2Order.Data));
        /* 
        TODO decide if we want dynamic price checker or user puts minOut+deadline in order creation
        (
            GPv2Order.Data memory _order,
            address _orderCreator,
            address _priceChecker,
            bytes memory _priceCheckerData
        ) = _decodeOrder(_encodedOrder);
        */


        // if order created by RSA with initiateTrade() then auto-approve.
        if(orders[_tradeHash] != 0) {
            if(_order.validTo <= block.timestamp) {
                revert InvalidTradeDeadline();
            }

            return ERC_1271_MAGIC_VALUE;
        } else {
            /*
            Dont currently support offchain signing of orders
            bc if anyone submits vs lender/borrower changes 
            game theoretic assumpotions about submitting optimal orders
            
            We currently dont have to check any of these conditions bc
            we create our own orders programmatically in generateOrder().
            If orders[tradeId] passes then trade params are valid.
            */

            // // Secondary verification option for fully offchain order submissions
            // // w/o initiateOrder() to allow fully gasless UX for users
            // // If order not created by RSA then manually check order data and verify signature with EIP712
            // // Not valid because anyone could submit orders on behalf of RSA not just lender/borrower like in initiateOrder
            // // Can resolve by passing custom data but would need order signed by either party,
            // // decode and recover signer address in isValidSignature, then resign with EIP1271 as RSA?

            
            // // check that order was created for/signed by this RSA
            // if(_order.hash(DOMAIN_SEPARATOR()) != _tradeHash) {
            //     // same as `orders[_tradeHash] != 0` if they had used initiateOrder()
            //     revert InvalidTradeDomain();
            // }

            // if(_order.kind != GPv2Order.KIND_SELL) {
            //     revert MustBeSellOrder();
            // }

            // if(_order.sellAmount == 0) {
            //     revert MustSellMoreThan0();
            // }

            // // ensure we are buying the right token. 
            // // Cant sell creditToken to prevent griefing
            // if(_order.sellToken == creditToken || _order.buyToken != creditToken) {
            //     revert InvalidTradeTokens();
            // }

            // // pretty sure we dont care about fill status
            // // if(_order.partiallyFillable) { revert MustFillOrder(); }

            // // ensure tokens are sent directly to contracts and not stored in Balancer vault.
            // if(
            //     _order.sellTokenBalance == GPv2Order.BALANCE_ERC20 && 
            //     _order.buyTokenBalance == GPv2Order.BALANCE_ERC20
            // ) {
            //     revert InvalidTradeBalanceDestination();
            // }

            return ERC_1271_NON_MAGIC_VALUE;
        }

        // if not manually initiated or invalid order then revert
        return ERC_1271_NON_MAGIC_VALUE;
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
    * @notice Allows lender to approve more revenue streams to their RSA to increase repayment speed
    * @param revenueContract - the contract to add revenue for
    * @param claimFunc - Function to call on revenue contract tto claim revenue into the Spigot.
    * @param transferFunc - Function on revenue contract to call to transfer ownership. MUST only take 1 parameter that is the new owner
    * @return bool - if update was successful
    *
    */
    function addSpigot(address revenueContract, bytes4 claimFunc, bytes4 transferFunc) external returns(bool) {
        if(msg.sender != lender) {
            revert NotLender();
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

    function _repay() internal returns(uint256) {
        // The lender can only deposit once and lent tokens are NOT stored in this contract
        // so any new tokens are from revenue and we just check against current revenue deposits
        uint256 currBalance = ERC20(creditToken).balanceOf(address(this));
        uint256 newPayments = currBalance - claimableAmount;
        uint256 maxPayable = totalOwed; // cache in memory

        if(newPayments > maxPayable) {
            // if revenue > debt then repay all debt
            // and return excess to borrower
            claimableAmount = maxPayable;
            totalOwed = 0;
            emit Repay(maxPayable);
            return maxPayable;
            // borrower can now sweep() excess funds + releaseSpigot()
        } else {
            claimableAmount += newPayments;
            totalOwed -= newPayments;
            emit Repay(newPayments);
            return newPayments;
        }
    }

    function _assertOrderParams(
        address _revenueToken,
        uint256 _sellAmount,
        uint256 _minBuyAmount,
        uint32 _deadline
    ) internal pure {
        // require()s ordered by least gas intensive
        /// @dev https://docs.cow.fi/tutorials/how-to-submit-orders-via-the-api/4.-signing-the-order#security-notice
        require(_sellAmount != 0, "Invalid trade amount");
        require(totalOwed != 0, "No debt to trade for");
        require(_revenueToken != creditToken, "Cant sell token being bought");
        if(
            _deadline < block.timestamp ||
            _deadline > block.timestamp + MAX_TRADE_DEADLINE
        ) { 
            revert InvalidTradeDeadline();
        }
    }

    function generateOrder(
        address _sellToken, 
        uint256 _sellAmount, 
        uint256 _minBuyAmount, 
        uint32 _deadline
    )
        public view
        returns(GPv2Order.Data memory) 
    {
        return GPv2Order.Data({
            kind: GPv2Order.KIND_SELL,  // market sell revenue tokens, dont specify zamount bought.
            receiver: address(this),    // hardcode so trades are trustless 
            sellToken: _sellToken,
            buyToken: creditToken,      // hardcode so trades are trustless 
            sellAmount: _sellAmount,
            buyAmount: _minBuyAmount,
            feeAmount: 0,
            validTo: _deadline,
            appData: 0,                 // no custom data for isValidsignature
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    /**
    * @notice gets the contract to wrap chains native asset into ERC20 for trading.
    *       MUST conform to WETH interface even if ETH is not native asset
    * @dev do not need to worry about network forks affecting wrapper contract address
    * so dont need to update like EIP721 domain separator
    */
    function _setWrapperForNetwork() internal {
        address weth = getWrapper();
        if(address(0) == weth) {
            revert UnsupportedNetwork();
        }

        WETH = IWETH(weth);
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
}
