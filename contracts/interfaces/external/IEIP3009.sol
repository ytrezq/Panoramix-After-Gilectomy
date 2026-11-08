// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IEIP3009
/// @notice Interface for EIP-3009: Transfer With Authorization
interface IEIP3009 {
  /// @notice Execute a transfer with a signed authorization (EOA signature)
  /// @dev SECURITY: anyone may submit this call (no `msg.sender` restriction). Integrators that
  /// pair the transfer with downstream logic (e.g. swap, deposit, redeem) MUST use
  /// `receiveWithAuthorization` instead: a mempool watcher can otherwise frontrun the original
  /// transaction with a raw `transferWithAuthorization`, burning the nonce so the original
  /// reverts while the funds still move - causing the post-transfer logic to be skipped.
  /// Use this primitive only for direct payouts to a passive recipient (`msg.sender != to`).
  /// @param from The address of the sender
  /// @param to The address of the recipient
  /// @param value The amount of tokens to transfer
  /// @param validAfter The timestamp after which the authorization is valid
  /// @param validBefore The timestamp before which the authorization is valid
  /// @param nonce The nonce of the authorization
  /// @param v The recovery id of the signature
  /// @param r The r value of the signature
  /// @param s The s value of the signature
  function transferWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external;

  /// @notice Execute a transfer with a signed authorization (EIP-1271 compatible)
  /// @dev SECURITY: see the EOA overload - this primitive is frontrun-prone and must not be used
  /// when the transfer is bound to follow-on logic. Use `receiveWithAuthorization` in that case.
  /// @param from The payer's address (Authorizer)
  /// @param to The payee's address
  /// @param value The amount to be transferred
  /// @param validAfter The time after which this is valid (unix time)
  /// @param validBefore The time before which this is valid (unix time)
  /// @param nonce The nonce
  /// @param signature The signature bytes signed by an EOA wallet or a contract wallet
  function transferWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes calldata signature
  )
    external;

  /// @notice Receive a transfer with a signed authorization (EOA signature)
  /// @dev The caller must be the payee (`to` address). This has an additional check to ensure
  /// that the payee's address matches the caller of this function to prevent front-running attacks.
  /// @param from The payer's address (Authorizer)
  /// @param to The payee's address
  /// @param value The amount to be transferred
  /// @param validAfter The time after which this is valid (unix time)
  /// @param validBefore The time before which this is valid (unix time)
  /// @param nonce The nonce
  /// @param v The recovery id of the signature
  /// @param r The r value of the signature
  /// @param s The s value of the signature
  function receiveWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external;

  /// @notice Receive a transfer with a signed authorization (EIP-1271 compatible)
  /// @dev The caller must be the payee (`to` address)
  /// @param from The payer's address (Authorizer)
  /// @param to The payee's address
  /// @param value The amount to be transferred
  /// @param validAfter The time after which this is valid (unix time)
  /// @param validBefore The time before which this is valid (unix time)
  /// @param nonce The nonce
  /// @param signature The signature bytes signed by an EOA wallet or a contract wallet
  function receiveWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes calldata signature
  )
    external;

  /// @notice Attempt to cancel an authorization
  /// @dev Works only if the authorization is not yet used.
  /// EOA wallet signatures should be packed in the order of r, s, v.
  /// @param authorizer Authorizer's address
  /// @param nonce Nonce of the authorization
  /// @param v The recovery id of the signature
  /// @param r The r value of the signature
  /// @param s The s value of the signature
  function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external;

  /// @notice Cancel an authorization (EIP-1271 compatible)
  /// @param authorizer Authorizer's address
  /// @param nonce Nonce of the authorization
  /// @param signature The signature bytes signed by an EOA wallet or a contract wallet
  function cancelAuthorization(address authorizer, bytes32 nonce, bytes calldata signature) external;

  /// @notice Returns the state of an authorization
  /// @param authorizer Authorizer's address
  /// @param nonce Nonce of the authorization
  /// @return true if the nonce is used
  function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}
