// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {CrossChainMultisig} from "../../global/CrossChainMultisig.sol";
import {CrossChainCall} from "../../interfaces/ICrossChainMultisig.sol";

contract CrossChainMultisigHarness is CrossChainMultisig {
    constructor(address[] memory initialSigners, uint8 _confirmationThreshold, address _owner)
        CrossChainMultisig(initialSigners, _confirmationThreshold, _owner)
    {}

    // Expose internal functions for testing
    function exposed_addSigner(address newSigner) external {
        _addSigner(newSigner);
    }

    function exposed_setConfirmationThreshold(uint8 newConfirmationThreshold) external {
        _setConfirmationThreshold(newConfirmationThreshold);
    }

    function exposed_verifyBatch(CrossChainCall[] memory calls, bytes32 prevHash) external view {
        _verifyBatch(calls, prevHash);
    }

    function exposed_verifySignatures(bytes[] memory signatures, bytes32 structHash) external view returns (uint256) {
        return _verifySignatures(signatures, structHash);
    }

    function exposed_executeBatch(CrossChainCall[] memory calls, bytes32 batchHash) external {
        _executeBatch(calls, batchHash);
    }

    // Add setter for lastBatchHash
    function setLastBatchHash(bytes32 newHash) external {
        _executedBatchHashes.push(newHash);
    }
}
