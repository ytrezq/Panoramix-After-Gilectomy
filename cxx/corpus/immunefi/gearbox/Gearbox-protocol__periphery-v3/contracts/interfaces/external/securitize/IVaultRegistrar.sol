// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IVaultRegistrar {
    /// @notice Registers a vault address under an existing investor identity
    /// @param vault The vault address to register
    /// @param investor The investor's wallet address (signer)
    /// @param deadline Unix timestamp after which the signature is invalid
    /// @param signature EIP-712 signature that supports EOA (ECDSA) and smart contract wallets (ERC-1271)
    function registerVault(address vault, address investor, uint256 deadline, bytes calldata signature) external;

    /// @notice Checks if a vault is registered for an investor
    /// @param vault The vault address to check
    /// @param investor The investor's wallet address
    /// @return `true` if the vault is registered for the investor
    function isRegistered(address vault, address investor) external view returns (bool);

    /// @notice Returns the token address
    /// @return The token address
    function token() external view returns (address);

    /// @notice Returns the current nonce for an investor-operator pair
    /// @param investor The investor wallet address
    /// @param operator The operator address
    /// @return The current nonce
    function operatorNonce(address investor, address operator) external view returns (uint256);

    /// @notice Invalidates all signatures the caller previously granted to an operator
    /// @param operator The operator address whose permission should be invalidated
    function invalidateOperatorPermission(address operator) external;

    /// @notice Grants operator role to an address
    /// @param operator Address to grant operator role
    function addOperator(address operator) external;
}
