// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title LibAuthorization
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Derives the EIP-3009 nonce that binds the Parallelizer's `*WithAuthorization` entry
/// points to their full swap/redeem intent (output `to`, slippage, deadline, ...), closing the
/// front-running gap left by vanilla `receiveWithAuthorization` which only commits to the token
/// transfer itself.
/// @dev Off-chain, the authorizer signs a standard EIP-3009 `ReceiveWithAuthorization` with
/// `nonce = compute*Nonce(...)`. The facet recomputes the same value from the call arguments and
/// forwards it to the token; tampering with any bound field makes the signature invalid. Replay
/// protection is provided by the token's own `authorizationStates` mapping; retries use a fresh
/// `userSalt`.
library LibAuthorization {
  // keccak256("SwapExactInputWithAuthorization(address from,address tokenIn,address tokenOut,uint256 amountIn,uint256
  // amountOutMin,address to,uint256 deadline,bytes32 userSalt)")
  bytes32 internal constant SWAP_EXACT_INPUT_WITH_AUTHORIZATION_TYPEHASH =
    0x9be969f74c66b263054aa69cfac8412777a0dc17ab007f81682c6b156ba06d79;

  // keccak256("SwapExactOutputWithAuthorization(address from,address tokenIn,address tokenOut,uint256
  // amountOut,uint256 amountInMax,address to,uint256 deadline,bytes32 userSalt)")
  bytes32 internal constant SWAP_EXACT_OUTPUT_WITH_AUTHORIZATION_TYPEHASH =
    0x41378613b6b468c26472b6d9a40faaeaf3c63b23ae57d1d7e3a7c3d2c356b1ed;

  // keccak256("RedeemWithAuthorization(address from,uint256 amount,address receiver,uint256 deadline,bytes32
  // minAmountOutsHash,bytes32 forfeitTokensHash,bytes32 expectedTokensHash,bytes32 userSalt)")
  bytes32 internal constant REDEEM_WITH_AUTHORIZATION_TYPEHASH =
    0xb6577f08e668b53303325a19233e8315142d69bedb6d7e1d8d0e9af2473486d4;

  function computeSwapExactInputNonce(
    address from,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    address to,
    uint256 deadline,
    bytes32 userSalt
  )
    internal
    pure
    returns (bytes32)
  {
    return keccak256(
      abi.encode(
        SWAP_EXACT_INPUT_WITH_AUTHORIZATION_TYPEHASH,
        from,
        tokenIn,
        tokenOut,
        amountIn,
        amountOutMin,
        to,
        deadline,
        userSalt
      )
    );
  }

  function computeSwapExactOutputNonce(
    address from,
    address tokenIn,
    address tokenOut,
    uint256 amountOut,
    uint256 amountInMax,
    address to,
    uint256 deadline,
    bytes32 userSalt
  )
    internal
    pure
    returns (bytes32)
  {
    return keccak256(
      abi.encode(
        SWAP_EXACT_OUTPUT_WITH_AUTHORIZATION_TYPEHASH,
        from,
        tokenIn,
        tokenOut,
        amountOut,
        amountInMax,
        to,
        deadline,
        userSalt
      )
    );
  }

  /// @param expectedTokensHash `keccak256(abi.encodePacked(tokens))` over the redemption output list the
  /// authorizer was quoted, binding token identity and ordering rather than raw amounts alone
  function computeRedeemNonce(
    address from,
    uint256 amount,
    address receiver,
    uint256 deadline,
    uint256[] memory minAmountOuts,
    address[] memory forfeitTokens,
    bytes32 expectedTokensHash,
    bytes32 userSalt
  )
    internal
    pure
    returns (bytes32)
  {
    return keccak256(
      abi.encode(
        REDEEM_WITH_AUTHORIZATION_TYPEHASH,
        from,
        amount,
        receiver,
        deadline,
        keccak256(abi.encodePacked(minAmountOuts)),
        keccak256(abi.encodePacked(forfeitTokens)),
        expectedTokensHash,
        userSalt
      )
    );
  }
}
