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

import {RateLimitLib} from "contracts/globalMarkets/issuer/rateLimit/RateLimitLib.sol";

/**
 * @title  RateLimitStorage
 * @author Ondo Finance
 * @notice EIP-7201 namespaced storage for the rate limiter: the gross tiers grouped per direction,
 *         plus the shared global net bucket
 */
library RateLimitStorage {
  /**
   * @notice The rate limiter's storage layout
   * @param  mintLimits   The gross tiers (global / token / user / default-user) for mints
   * @param  redeemLimits The gross tiers (global / token / user / default-user) for redeems
   * @param  globalNet    The shared signed net-notional bucket
   */
  struct Layout {
    RateLimitLib.DirectionalRateLimits mintLimits;
    RateLimitLib.DirectionalRateLimits redeemLimits;
    RateLimitLib.NetRateLimit globalNet;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Storage
  // ─────────────────────────────────────────────────────────────────────────────

  string internal constant STORAGE_ID = "ondo.rate.limit.storage";
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
