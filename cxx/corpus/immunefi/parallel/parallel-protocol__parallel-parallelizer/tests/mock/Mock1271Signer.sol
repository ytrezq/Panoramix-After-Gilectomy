// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

interface IERC1271 {
  function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}

/// @notice Minimal EIP-1271 signer that recognizes a single preconfigured signature blob,
/// regardless of its length. Used to verify that the Parallelizer auth path accepts
/// non-65-byte contract signatures.
contract Mock1271Signer is IERC1271 {
  bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

  bytes32 public expectedHash;
  bytes public expectedSignature;

  function setAuthorized(bytes32 hash, bytes calldata signature) external {
    expectedHash = hash;
    expectedSignature = signature;
  }

  function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
    if (hash == expectedHash && keccak256(signature) == keccak256(expectedSignature)) {
      return MAGIC_VALUE;
    }
    return 0xffffffff;
  }
}
