// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {ITimeLock} from "@gearbox-protocol/permissionless/contracts/interfaces/ITimeLock.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

contract BatchesChain is IVersion {
    /// @notice Contract type
    bytes32 public constant override contractType = "BATCHES_CHAIN";

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Check if tx is queued in TimeLock
    /// @dev Reverts if tx was not executed
    function revertIfQueued(bytes32 txHash) external view {
        if (ITimeLock(msg.sender).queuedTransactions(txHash)) {
            revert("BatchesChain: transaction isn't executed yet");
        }
    }
}
