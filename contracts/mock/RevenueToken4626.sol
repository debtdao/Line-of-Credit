pragma solidity 0.8.9;

import "./RevenueToken.sol";

contract RevenueToken4626 is RevenueToken {
    address private _asset;
    uint256 private _multiplier;

    constructor(address assetAddr) {
        _asset = assetAddr;
        _multiplier = 1;
    }

    function setAssetAddress(address assetAddr) external {
        _asset = assetAddr;
    }

    function setAssetMultiplier(uint256 multiplier) public {
        _multiplier = multiplier;
    }

    // mimic eip-4626
    function asset() public view returns (address) {
        return _asset;
    }

    // mimic eip-4626
    function previewRedeem(uint256 amount) public view returns (uint256) {
        return amount * _multiplier;
    }
}
