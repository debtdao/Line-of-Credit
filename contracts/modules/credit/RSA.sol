// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../spigot/Spigot.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISpigot} from "../../interfaces/ISpigot.sol";
import { MutualConsent } from "../../utils/MutualConsent.sol";

import "./ECDSA.sol";

contract RevenueShareAgreement is ERC20, MutualConsent {
    using ECDSA for bytes32;
    using SafeERC20 for ERC20;

    address public spigot;
    address public lender;
    address public lender;
    address public borrower;
    address public creditToken;

    // denomainated in creditToken
    uint256 public initialPrincipal;
    uint256 public totalOwed;
    uint256 public currentDeposits; // total repaid from revenue - total withdrawn by

    /// @notice  revenue token -> 8 decimal price in credit tokens.
    /// e.g. 2e8 == means we must sell <= 0.5 revenue tokens to buy 1 credit token
    mapping(address => uint16) public floorPrices;
    bytes32 public finalizedTradeHash;
    uint8 constant MAX_SPLIT = 100;

    error InvalidPaymentSetting;
    error CantSweepWhileInDebt;
    error DepositsFull;
    error NotBorrower;

    constructor(
        address _spigot,
        address _borrower,
        uint16 _revenueSplit,
        address _creditToken,
        uint256 _initialPrincipal,
        uint256 _totalOwed
    ) {
        spigot = _spigot;
        borrower = _borrower;

        if(_initialPrincipal > _totalOwed) {
            revert InvalidPaymentSetting();
        }

        creditToken = _creditToken;
        initialPrincipal = _initialPrincipal;
        totalOwed = _totalOwed;
    }

    function deposit() {
        if(lender != address(0)) {
            revert DepositsFull();
        }

        lender = msg.sender;
        _mint(msg.sender, _totalOwed);

        ERC20(creditToken).transferFrom(msg.sender, borrower, initialPrincipal);
    }

    function claim(uint256 _amount) external {
        _burn(msg.sender, _amount);
        ERC20(creditToken).transfer(msg.sender, _amount);
        return true;
    }

    function sweep(address _token, uint256 _amount) external {
        if(msg.sender != borower) {
            revert NotBorrower();
        }
        if(totalOwed != 0) {
            revert CantSweepWhileInDebt();
        }

        ERC20(_token).transfer(msg.sender, ERC20(_token).balanceOf(address(this)));
        
        return true;
    }   

    function finalizeTrade(bytes32 tradeHash) external {
        require(msg.sender == lender, "Caller must be lender");
        require(tradeHash == finalizedTradeHash, "Invalid trade hash");

        // require(ownerTokens[creditToken] >= totalRevenue, "Insufficient funds");
        // uint256 tokensBurned = ownerTokens[creditToken];
        // ownerTokens[creditToken] = 0;
        // IERC20(creditToken).burn(tokensBurned);

        totalRevenue += totalRevenue;

        totalRevenue = 0;
        finalizedTradeHash = bytes32(0);

        emit TradeFinalized(tradeHash);
    }

    function initiateTrade(
        uint256 tradeAmount,
        uint256 minPrice,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(tradeAmount > 0 && tradeAmount <= totalRevenue, "Invalid trade amount");
        require(deadline >= block.timestamp, "Trade deadline has passed");

        bytes32 tradeHash = keccak256(
            abi.encodePacked(address(this), tradeAmount, minPrice, deadline)
        ).toEthSignedMessageHash();

        require(
            ECDSA.recover(tradeHash, signature) == lender,
            "Signature must be from lender"
        );

        finalizedTradeHash = tradeHash;
        totalRevenue = minPrice;
        emit TradeInitiated(tradeHash, tradeAmount, minPrice, deadline);
    }

    function trade(
        address revenueContract,
        address token,
        uint256 minPrice,
        bytes calldata data
    ) external {
        require(revenueContracts[revenueContract].revenueContract != address(0), "Invalid revenue contract");
        require(spigot.isWhitelisted(data[0:4]), "Function not whitelisted");
        uint256 balanceBefore = spigot.getBalance(token);
        (bool success, ) = revenueContract.call(data);
        require(success, "Trade failed");
        uint256 balanceAfter = spigot.getBalance(token);
        require(balanceAfter > balanceBefore, "No revenue received");
        require(
            spigot.getNormalizedPrice(
                token,
                balanceAfter - balanceBefore,
                spigot.getSupply(token),
                RSA.balanceOf(address(this))
            ) >= minPrice,
            "Price below minimum"
        );
    }

    function setFloorPrice(address revenueToken, uint16 price) mutualConsent(borrower, lender) {
        floorPrices[revenueToken] = price;
        return true;
    }

    event TradeInitiated(
        bytes32 indexed tradeHash,
        uint256 indexed tradeAmount,
        uint256 indexed minPrice,
        uint256 deadline
    );
    event TradeFinalized(bytes32 indexed tradeHash);
}
