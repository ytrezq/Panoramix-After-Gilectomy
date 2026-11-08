// SPDX-License-Identifier: BUSL-1.1
/*

      ▄▄█████████▄
   ╓██▀└ ,╓▄▄▄, '▀██▄
  ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
  ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
   ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
      ╙▀▀██████R⌐

 */
pragma solidity ^0.8.4;

/**
 * @title  IssuerStorage
 * @author Ondo Finance
 * @notice EIP-7201 namespaced storage layout for the GM issuer contract
 */
library IssuerStorage {
  /**
   * @notice The GM issuer's storage layout
   * @param  gmTokenManager                  The GMTokenManager (registry/oracle source)
   * @param  usedNonces                      Consumed nonces, keyed signer → nonce
   * @param  processedTokenizationRequestIds Processed mint requestId hashes (idempotency)
   * @param  gmTokenBySymbol                 Token symbol → GM token
   * @param  symbolByGmToken                 GM token → token symbol (strict inverse)
   * @param  network                         The configured network name
   * @param  networkHash                     keccak256 of `network` (cheap comparison)
   * @param  perTxMintCapUSD                 The per-tx mint cap (USD, 18 decimals)
   * @param  mintsPaused                     Whether mints are paused
   * @param  redeemsPaused                   Whether new redeems are paused
   */
  struct Layout {
    address gmTokenManager;
    mapping(address => mapping(uint256 => bool)) usedNonces;
    mapping(bytes32 => bool) processedTokenizationRequestIds;
    mapping(string => address) gmTokenBySymbol;
    mapping(address => string) symbolByGmToken;
    string network;
    bytes32 networkHash;
    uint256 perTxMintCapUSD;
    bool mintsPaused;
    bool redeemsPaused;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Storage
  // ─────────────────────────────────────────────────────────────────────────────

  string internal constant STORAGE_ID = "ondo.issuer.storage";
  bytes32 internal constant STORAGE_POSITION = keccak256(
    abi.encode(uint256(keccak256(abi.encodePacked(STORAGE_ID))) - 1)
  ) & ~bytes32(uint256(0xff));

  function layout() internal pure returns (Layout storage s) {
    bytes32 position = STORAGE_POSITION;
    assembly {
      s.slot := position
    }
  }
}
