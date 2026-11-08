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

import {IssuerTypes} from "contracts/globalMarkets/issuer/issuerLib/IssuerTypes.sol";

/**
 * @title  IGMIssuerManager
 * @author Ondo Finance
 * @notice Interface for the GM issuer: Alpaca-signed in-kind mints and user-initiated redeem
 *         burns, with a composable menu of USD rate limits (global / per-token / per-user gross
 *         + a global net-notional limit)
 */
interface IGMIssuerManager {
  // ─────────────────────────────────────────────────────────────────────────────
  // Mint
  // ─────────────────────────────────────────────────────────────────────────────

  function processMint(
    IssuerTypes.MintRequest calldata req,
    bytes calldata signature,
    uint256 amount
  ) external;

  function processMintPrivileged(
    IssuerTypes.MintRequest calldata req,
    bytes calldata signature,
    uint256 amount
  ) external;

  // ─────────────────────────────────────────────────────────────────────────────
  // Redeem
  // ─────────────────────────────────────────────────────────────────────────────

  function redeem(address gmToken, uint256 amount) external;

  function redeemPrivileged(address gmToken, uint256 amount) external;

  // ─────────────────────────────────────────────────────────────────────────────
  // Config
  // ─────────────────────────────────────────────────────────────────────────────

  function setSupportedGmToken(string calldata tokenSymbol, address gmToken) external;

  function removeSupportedGmToken(string calldata tokenSymbol) external;

  function setPerTxMintCap(uint256 cap) external;

  function setGlobalMintRateLimit(uint256 limit, uint48 window) external;

  function setGlobalRedeemRateLimit(uint256 limit, uint48 window) external;

  function setTokenMintRateLimit(address token, uint256 limit, uint48 window) external;

  function setTokenRedeemRateLimit(address token, uint256 limit, uint48 window) external;

  function setUserMintRateLimit(bytes32 userId, uint256 limit, uint48 window) external;

  function setUserRedeemRateLimit(bytes32 userId, uint256 limit, uint48 window) external;

  function setDefaultUserMintRateLimit(uint256 limit, uint48 window) external;

  function setDefaultUserRedeemRateLimit(uint256 limit, uint48 window) external;

  function setGlobalNetRateLimit(uint256 limit, uint48 window) external;

  function removeGlobalMintRateLimit() external;

  function removeGlobalRedeemRateLimit() external;

  function removeTokenMintRateLimit(address token) external;

  function removeTokenRedeemRateLimit(address token) external;

  function removeUserMintRateLimit(bytes32 userId) external;

  function removeUserRedeemRateLimit(bytes32 userId) external;

  function removeDefaultUserMintRateLimit() external;

  function removeDefaultUserRedeemRateLimit() external;

  function removeGlobalNetRateLimit() external;

  // ─────────────────────────────────────────────────────────────────────────────
  // Pause
  // ─────────────────────────────────────────────────────────────────────────────

  function pauseMints() external;

  function unpauseMints() external;

  function pauseRedeems() external;

  function unpauseRedeems() external;

  // ─────────────────────────────────────────────────────────────────────────────
  // Views
  // ─────────────────────────────────────────────────────────────────────────────

  function hashMintRequest(IssuerTypes.MintRequest calldata req) external pure returns (bytes32);

  function digestMintRequest(IssuerTypes.MintRequest calldata req) external view returns (bytes32);

  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function isNonceUsed(address signer, uint256 nonce) external view returns (bool);

  function isRequestProcessed(bytes32 requestIdHash) external view returns (bool);

  function gmTokenBySymbol(string calldata tokenSymbol) external view returns (address);

  function isSupportedGmToken(address gmToken) external view returns (bool);

  function globalMintRateLimit()
    external
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available);

  function globalRedeemRateLimit()
    external
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available);

  function tokenMintRateLimit(address token)
    external
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available);

  function tokenRedeemRateLimit(address token)
    external
    view
    returns (uint256 limit, uint48 window, bool active, uint256 capacityUsed, uint256 available);

  function userMintRateLimit(bytes32 userId)
    external
    view
    returns (
      uint256 limit,
      uint48 window,
      bool overrideActive,
      uint256 capacityUsed,
      uint256 available
    );

  function userRedeemRateLimit(bytes32 userId)
    external
    view
    returns (
      uint256 limit,
      uint48 window,
      bool overrideActive,
      uint256 capacityUsed,
      uint256 available
    );

  function defaultUserMintRateLimit()
    external
    view
    returns (uint256 limit, uint48 window, bool active);

  function defaultUserRedeemRateLimit()
    external
    view
    returns (uint256 limit, uint48 window, bool active);

  function globalNetRateLimit()
    external
    view
    returns (int256 net, uint256 limit, uint48 window, bool active);

  function perTxMintCapUSD() external view returns (uint256);

  function gmTokenManager() external view returns (address);

  function network() external view returns (string memory);

  function gmIdentifier() external pure returns (address);

  function alpacaItnIdentifier() external pure returns (address);

  function mintsPaused() external view returns (bool);

  function redeemsPaused() external view returns (bool);
}
