# Hedera: not an EVM-contract program

- Scope: Blockchain/DLT and websites/applications only: hiero-ledger/hiero-consensus-node (Java), hiero-mirror-node (Java),
  hiero-json-rpc-relay (TypeScript), hiero-cryptography, the transaction tool and the Go/JS/Java SDKs. No smart contract asset,
  no contract address.
- Hedera runs EVM bytecode (Hedera Smart Contract Service), but the EVM and its system contracts (HTS 0x167 etc.) are implemented
  natively in Java; the in-scope assets are node software, relay and SDKs.
- The only Solidity in these repositories is test fixtures (checked 2026-11-07: hiero-consensus-node 339 files under
  `hedera-node/test-clients/src/main/resources`, json-rpc-relay `tests/server/contracts`, mirror-node `test/` and `web3/src/test*`),
  not in-scope contracts: nothing copied.
