# Stargate

- Scope: primacy of impact; the Stargate V2 deployments (stargate-protocol/stargate-v2 tree/main/packages/stg-evm-v2/deployments,
  i.e. every chain's deployed StargatePool/OFT/TokenMessaging/... contracts); lzMultiCall and TransferDelegate on Ethereum and
  lzMultiCall on Solana.
- Copied stargate-protocol/stargate-v2 at main (35e04fd9, BUSL-1.1): the EVM sources of packages/stg-evm-v2 (src, test,
  script) with the npm packages they import (LayerZero lz-evm-oapp-v2/protocol-v2, solidity-examples, OpenZeppelin);
  scope path packages/stg-evm-v2.
- Not covered: lzMultiCall (0xAcdDAC6C...) and TransferDelegate (0x72fAEbF5...): LayerZero Value Transfer API contracts
  (LZMulticall wrapper and its paired delegate); their source is not in stargate-v2 and no public repository was found.
- Left out: the Solana lzMultiCall (non-EVM); LayerZero-Labs/Audits (reports).
- The deployments directory's per-chain addresses were not checked against this commit.
