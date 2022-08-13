// forked from https://github.com/IndexCoop/index-coop-smart-contracts/blob/master/contracts/lib/MutualConsent.sol

pragma solidity 0.8.9;

/**
 * @title MutualConsent
 * @author Set Protocol
 *
 * The MutualConsent contract contains a modifier for handling mutual consents between two parties
 */
abstract contract MutualConsent {
    /* ============ State Variables ============ */

    // Mapping of upgradable units and if consent has been initialized by other party
    mapping(bytes32 => bool) public mutualConsents;

    error Unauthorized();

    /* ============ Events ============ */

    event MutualConsentRegistered(
        bytes32 _consentHash
    );

    /* ============ Modifiers ============ */

    /**
    * @notice - allows a function to be called if only two specific stakeholders signoff on the tx data
    *         - signers can be anyone. only two signers per contract or dynamic signers per tx.
    */
    modifier mutualConsent(address _signerOne, address _signerTwo) {
      if(_mutualConsent(_signerOne, _signerTwo))  {
        // Run whatever code needed 2/2 consent
        _;
      }
    }

    function _mutualConsent(address _signerOne, address _signerTwo) internal returns(bool) {
        if(msg.sender != _signerOne && msg.sender != _signerTwo) { revert Unauthorized(); }

        address nonCaller = _getNonCaller(_signerOne, _signerTwo);

        // The consent hash is defined by the hash of the transaction call data and sender of msg,
        // which uniquely identifies the function, arguments, and sender.
        bytes32 expectedHash = keccak256(abi.encodePacked(msg.data, nonCaller));

        if (!mutualConsents[expectedHash]) {
            bytes32 newHash = keccak256(abi.encodePacked(msg.data, msg.sender));

            mutualConsents[newHash] = true;

            emit MutualConsentRegistered(newHash);

            return false;
        }

        delete mutualConsents[expectedHash];

        return true;
    }


    /* ============ Internal Functions ============ */

    function _getNonCaller(address _signerOne, address _signerTwo) internal view returns(address) {
        return msg.sender == _signerOne ? _signerTwo : _signerOne;
    }
}
