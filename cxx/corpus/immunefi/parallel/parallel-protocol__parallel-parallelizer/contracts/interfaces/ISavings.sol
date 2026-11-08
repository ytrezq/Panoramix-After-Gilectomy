// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { IEIP3009 } from "./external/IEIP3009.sol";

/// @title ISavings
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
interface ISavings is IEIP3009 {
  /// @notice Deposit the underlying asset on behalf of `owner` and mint shares to `receiver`.
  /// @param savingsSignature Signature over `DEPOSIT_WITH_AUTHORIZATION_TYPEHASH` against the
  /// Savings contract's EIP-712 domain, binding `receiver` to prevent relayer front-running.
  /// @param tokenSignature Standard EIP-3009 `ReceiveWithAuthorization` signature against the
  /// underlying asset's EIP-712 domain, authorizing the transfer of `assets` into this contract.
  function depositWithAuthorization(
    uint256 assets,
    address receiver,
    address owner,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes calldata savingsSignature,
    bytes calldata tokenSignature
  )
    external
    returns (uint256 shares);

  /// @notice Burn `shares` from `owner` and send the underlying asset to `receiver`.
  /// @dev Signature is over `REDEEM_WITH_AUTHORIZATION_TYPEHASH` against the Savings contract's
  /// EIP-712 domain and binds `receiver` to prevent relayer front-running.
  function redeemWithAuthorization(
    uint256 shares,
    address receiver,
    address owner,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external
    returns (uint256 assets);

  /// @notice EIP-1271 compatible variant of `redeemWithAuthorization`.
  function redeemWithAuthorization(
    uint256 shares,
    address receiver,
    address owner,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes calldata signature
  )
    external
    returns (uint256 assets);

  function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external;

  function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);

  // solhint-disable-next-line func-name-mixedcase
  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function estimatedAPY() external view returns (uint256 apy);

  function computeUpdatedAssets(uint256 totalAssets, uint256 exp) external view returns (uint256);

  function pause() external;

  function unpause() external;

  function toggleTrusted(address trustedAddress) external;

  function setRate(uint208 newRate) external;

  function setMaxRate(uint256 newMaxRate) external;

  function recoverSurplus(address to) external returns (uint256 surplus);
}
