// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IConcreteAsyncVaultImpl} from "./IConcreteAsyncVaultImpl.sol";

/**
 * @title IConcreteBridgedAsyncVaultImpl
 * @notice Interface for the bridged async vault implementation that provides unbacked minting capabilities.
 * @dev This interface extends the async vault functionality with the ability to mint shares without
 *      depositing underlying assets, intended for cross-chain vault migrations during predeposit phases.
 */
interface IConcreteBridgedAsyncVaultImpl is IConcreteAsyncVaultImpl {
    /**
     * @dev Thrown when attempting to operate with zero amount.
     */
    error ZeroAmount();

    /**
     * @dev Thrown when attempting to mint unbacked shares when it's not the initial mint.
     */
    error NotInitialMint();

    /**
     * @dev Emitted when unbacked shares are minted.
     * @param shares The amount of shares minted without backing assets.
     */
    event UnbackedMint(uint256 shares);

    /**
     * @notice Mints vault shares without depositing any underlying assets.
     * @dev Only callable by addresses with VAULT_MANAGER role.
     * @dev Used only for vault migration where assets backing newly minted shares
     *      are expected to be updated directly on strategy level.
     * @dev Shares are minted for later distribution to end users.
     * @param shares Amount of shares to mint for the caller.
     */
    function unbackedMint(uint256 shares) external;
}

