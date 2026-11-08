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

import {IOndoIDRegistry} from "contracts/xManager/interfaces/IOndoIDRegistry.sol";
import {LimitOrderTypes} from "contracts/limit-order/LimitOrderTypes.sol";

/**
 * @title  LimitOrderStorage
 * @author Ondo Finance
 * @notice EIP-7201 namespaced storage layout shared by limit order contracts.
 */
library LimitOrderStorage {
  struct Layout {
    address tokenManager;
    IOndoIDRegistry ondoIDRegistry;
    LimitOrderTypes.LimitOrder[] orders;
    uint256 maxOrderDuration;
    bool paused;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Storage
  // ─────────────────────────────────────────────────────────────────────────────

  string internal constant STORAGE_ID = "ondo.limit.order.storage";
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
