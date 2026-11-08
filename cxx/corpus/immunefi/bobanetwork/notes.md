# Boba Network

- Scope: the Light Bridge proxies (Proxy__LightBridge) on Ethereum, Arbitrum, Optimism and Boba (2 addresses), plus the
  mainnet RPC/websocket and gateway websites.
- LightBridge.sol lives in bobanetwork/light-bridge (contracts/LightBridge.sol, per web search), which is no longer public
  (git: authentication required, raw: 404 on 2026-11-07): not available.
- Copied instead its public predecessor: bobanetwork/boba_legacy at branch develop (328f3f55, MIT), where the Light Bridge
  was still named Teleportation (packages/boba/contracts/contracts/Teleportation.sol, recorded as scope path). The copy holds
  all 345 .sol of that legacy monorepo (Boba v1 L1/L2 bridges, account-abstraction, ve-boba...) with their npm imports.
  It is not the deployed LightBridge implementation: main may prefer to drop it or fetch the verified source.
- Left out: bobanetwork/boba (develop): the current OP Stack based node repository, no bridge contract; the websites.
