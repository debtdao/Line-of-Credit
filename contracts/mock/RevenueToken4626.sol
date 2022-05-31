pragma solidity 0.8.9;

import "./RevenueToken.sol";

contract RevenueToken4626 is RevenueToken {

    address private _asset;
    uint private _multiplier;

    constructor() {
        _asset = address(this);
        _multiplier = 1;
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
    function previewRedeem(uint256 amount) public view returns(uint) {
        return amount * _multiplier;
    }
}
