// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @title IRedeemer
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev This interface is an authorized fork of Angle's `IRedeemer` interface
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/interfaces/IRedeemer.sol
interface IRedeemer {
  /// @notice Redeems `amount` of stablecoins from the system
  /// @param receiver Address which should be receiving the output tokens
  /// @param deadline Timestamp before which the redemption should have occured
  /// @param minAmountOuts Minimum amount of each token given back in the redemption to obtain
  /// @param expectedTokensHash `keccak256(abi.encodePacked(tokens))` over the output list the caller was
  /// quoted, as returned by `quoteRedemptionCurve`. The redemption reverts if the live list differs, since
  /// `minAmountOuts` is positional and a collateral rotation can change which token each entry protects
  /// @return tokens List of tokens returned
  /// @return amounts Amount given for each token in the `tokens` array
  function redeem(
    uint256 amount,
    address receiver,
    uint256 deadline,
    uint256[] memory minAmountOuts,
    bytes32 expectedTokensHash
  )
    external
    returns (address[] memory tokens, uint256[] memory amounts);

  /// @notice Same as the redeem function above with the additional feature to specify a list of `forfeitTokens` for
  /// which the Parallelizer system will not try to do a transfer to `receiver`.
  function redeemWithForfeit(
    uint256 amount,
    address receiver,
    uint256 deadline,
    uint256[] memory minAmountOuts,
    address[] memory forfeitTokens,
    bytes32 expectedTokensHash
  )
    external
    returns (address[] memory tokens, uint256[] memory amounts);

  /// @notice Same as `redeemWithForfeit` but using a single EIP-3009 authorization for the tokenP
  /// transfer.
  /// @dev The signed EIP-3009 nonce MUST equal `LibAuthorization.computeRedeemNonce(...)` so that
  /// mutating `receiver`, `amount`, `deadline`, `minAmountOuts`, `forfeitTokens` or `expectedTokensHash`
  /// invalidates the signature. `authData.nonce` carries the caller-chosen `userSalt`.
  /// @dev `expectedTokensHash` matters most here: a signature stays executable for its whole validity
  /// window, so without it a relayer could hold one until a collateral rotation reshuffles the output list
  function redeemWithAuthorization(
    uint256 amount,
    address receiver,
    uint256 deadline,
    uint256[] memory minAmountOuts,
    address[] memory forfeitTokens,
    bytes32 expectedTokensHash,
    bytes memory authData
  )
    external
    returns (address[] memory tokens, uint256[] memory amounts);

  /// @notice Simulate the exact output that a redemption of `amount` of stablecoins would give at a given block
  /// @return tokens List of tokens that would be given
  /// @return amounts Amount that would be obtained for each token in the `tokens` array
  function quoteRedemptionCurve(uint256 amount)
    external
    view
    returns (address[] memory tokens, uint256[] memory amounts);

  /// @notice Updates the normalizer variable by `amount`
  function updateNormalizer(uint256 amount, bool increase) external returns (uint256);
}
