pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";



contract CreditToken is Ownable, ERC20("Debt DAO Credit v1", "CREDIT-v1") {

    uint256 public globalCreditLimit; // maximum allowed CREDIT supply
    address constant debtFusePool = 0xA097856Ef35D368184DE4c3771E7F363B5Cb01E5; // TODO might need to change/add comptroller/cToken address


    mapping(address => bool) minters; // trusted parties to mint CREDIT to borrowers
    mapping(address => bool) userWhitelist; // address able to interact with CREDIT token

    event UpdateMinter(address indexed minter, bool indexed allowed);
    event UpdateWhitelist(address indexed user, bool indexed allowed);
    event UpdateCreditLimit(uint256 indexed newLimit);

    constructor(uint256 creditLimit) {
        globalCreditLimit = creditLimit;
        // Allow CREDIT to be supplied to fuse pool
        userWhitelist[debtFusePool] = true;
    }

    modifier onlyMinters() {
        require(minters[_msgSender()]);
        _;
    }

    /**
      @dev  Internal function hook called on all token transfers.
            Prevents CREDIT token from being sent to non-whitelisted addresses
            Minters are not allowed to receive CREDIT tokens unless explictly added to whitelist
      */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        require(userWhitelist[to], "CREDIT: reciepient not whitelisted");
    }

    /**
      @dev  Allows approved minters to increase CREDIT supply.
            Fails if requested mint puts total supply over cap set by DebtDAO governance.
      */
    function mint(address account, uint256 amount) external onlyMinters returns(bool) {
        require(totalSupply() + amount <= globalCreditLimit, "CREDIT: supply limit reached");
        require(totalSupply() + amount >= totalSupply(), "CREDIT: supply int overflow");

        // automatically whitelist user if not already approved
        if(!userWhitelist[account]) {
          userWhitelist[account] = true;
        }
        _mint(account, amount);
        // automatically approve fuse pool to use tokens because only thing to do with them
        _approve(account, debtFusePool, amount);
        
        return true;
    }


    function burnFrom(address account, uint256 amount) external onlyMinters returns(bool) {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _burn(account, amount);

        return true;
    }

    /** Owner functions to manage CREDIT token */

    /**
      @dev  Update the allowed total suppl.y Able to set it to lower than existing total supply to prevent further minting
     */

    function updateCreditLimit(uint256 newLimit) external onlyOwner {
        globalCreditLimit = newLimit;
        emit UpdateCreditLimit(newLimit);
    }

    function updateMinter(address minter, bool allowed) external onlyOwner {
        minters[minter] = allowed;
        emit UpdateMinter(minter, allowed);
    }

    function updateWhitelist(address user, bool allowed) external onlyOwner {
        userWhitelist[user] = allowed;
        emit UpdateWhitelist(user, allowed);
    }
}
