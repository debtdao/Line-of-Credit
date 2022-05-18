pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RevenueToken is ERC20("Token earned as revenue", "BRRRR") {

    address private _asset;
    uint private _multiplier;

    constructor() {
        _asset = address(this);
        _multiplier = 1;
    }

    function mint(address account, uint256 amount) external returns(bool) {
        _mint(account, amount);
        return true;
    }


    function burnFrom(address account, uint256 amount) external returns(bool) {
        _burn(account, amount);
        return true;
    }

    function setAssetAddress(address assetAddr) external {
        _asset = assetAddr;
    }

    function setAssetMultiplier(uint multiplier) public {
        _multiplier = multiplier;
    }

    // mimic eip-4626
    function asset() public returns(address) {
        return _asset;
    }

    // mimic eip-4626
    function convertToAssets(uint256 amount) public view returns(uint) {
        return amount * _multiplier;
    }
}
