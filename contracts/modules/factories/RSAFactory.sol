// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import {Clones} from  "openzeppelin/proxy/Clones.sol";
import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";
import {IRSAFactory} from "../../interfaces/IRSAFactory.sol";

import {RevenueShareAgreement} from "../../modules/credit/RevenueShareAgreement.sol";
import {Spigot} from "../../modules/spigot/Spigot.sol";

/**
 * @title   - Debt DAO RSAFactory
 * @notice  - Factory contract to deploy Spigot and Revenue Share Agreements
 * @dev     - use ERC-1167 immutable proxies
 */
contract RSAFactory is IRSAFactory {
    address rsaImpl;
    address spigotImpl;

    constructor() {
        rsaImpl = address(new RevenueShareAgreement());
        spigotImpl = address(new Spigot());
    }

    function deployRSA(
        address _spigot,
        address _borrower,
        address _creditToken,
        uint8 _revenueSplit,
        uint256 _initialPrincipal,
        uint256 _totalOwed,
        string memory _name,
        string memory _symbol
    ) public returns (address clone) {
        clone = Clones.clone(rsaImpl);
        RevenueShareAgreement(clone).initialize(
            _spigot,
            _borrower,
            _creditToken,
            _revenueSplit,
            _initialPrincipal,
            _totalOwed,
            _name,
            _symbol
        );

        emit DeployedRSA(_borrower, _spigot, _creditToken, clone, _initialPrincipal, _totalOwed, _revenueSplit);
    }

    function deploySpigot(
        address _owner,
        address _operator
    ) public returns (address clone) {
        clone =Clones.clone(spigotImpl);
        Spigot(payable(clone)).initialize(_owner, _operator);
        emit DeployedSpigot(clone, _owner, _operator);
    }
}