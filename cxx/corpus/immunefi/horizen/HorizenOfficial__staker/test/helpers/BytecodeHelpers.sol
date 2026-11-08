// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

/// @notice Helpers for comparing deployed bytecode across two independently compiled
/// instances of the same contract.
abstract contract BytecodeHelpers {
  /// @notice Strips the trailing solc metadata (the CBOR-encoded IPFS hash solc appends to
  /// runtime code) from `_code`. Two builds of byte-for-byte identical source can still embed
  /// a different metadata hash depending on the surrounding compilation context, so bytecode
  /// equality checks must ignore it to avoid false-negative mismatches unrelated to actual
  /// contract logic.
  function _stripMetadata(bytes memory _code) internal pure returns (bytes memory) {
    if (_code.length < 2) return _code;

    // The last 2 bytes encode the big-endian length of the CBOR metadata blob that precedes
    // them (see the Solidity metadata spec).
    uint256 _metadataLength = (uint256(uint8(_code[_code.length - 2])) << 8)
      | uint256(uint8(_code[_code.length - 1]));

    if (_metadataLength + 2 > _code.length) return _code;

    uint256 _newLength = _code.length - _metadataLength - 2;
    bytes memory _stripped = new bytes(_newLength);
    for (uint256 _i = 0; _i < _newLength; _i++) {
      _stripped[_i] = _code[_i];
    }
    return _stripped;
  }
}
