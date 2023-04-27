// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import {Clones} from  "openzeppelin/proxy/Clones.sol";
import {IModuleFactory} from "../../interfaces/IModuleFactory.sol";
import {IRSAFactory} from "../../interfaces/IRSAFactory.sol";
import {RevenueShareAgreement} from "../../modules/credit/RevenueShareAgreement.sol";

/**
 * @title   - Debt DAO Line Factory
 * @author  - Mom
 * @notice  - Facotry contract to deploy SecuredLine, Spigot, and Escrow contracts.
 * @dev     - Have immutable default values for Debt DAO system external dependencies.
 */
contract RSAFactory is IRSAFactory {
    address rsaImpl;

    constructor() {
        rsaImpl = address(new RevenueShareAgreement());
    }

    function createRSA(
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

        emit DeployRSA(_borrower, _spigot, _creditToken, _initialPrincipal, _totalOwed, _revenueSplit);
    }
}