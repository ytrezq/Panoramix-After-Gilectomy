// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @title  IOndoOwner
 * @notice Interface for the Ondo Owner contract, which manages administrative access control
 *         and ownership of various components in the Ondo bridge system.
 *
 * @dev    This is an abridged version of IOndoOwner to be used with the BridgeRegistrar.
 */
interface IOndoOwner {
    // ------------------- Messenger -------------------
    /**
     * @notice Registers a new token with the Messenger.
     * @param tokenId The unique identifier for the token.
     * @param tokenAddress The address of the token contract.
     * @return oftAddress The address of the newly created OndoOFT contract.
     */
    function registerToken(bytes32 tokenId, address tokenAddress) external returns (address oftAddress);
}
