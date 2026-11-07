# layerzero

- Scope: 10 smart-contract assets: EndpointV2, SendULN302 and ReceiveULN302 on Ethereum (EVM), the same on Aptos and
  Solana, the TON controller, and Primacy of Impact. The page links LayerZero-Labs/Audits only.
- EVM sources: LayerZero-Labs/LayerZero-v2 @ main (default branch, commit 9c741e7), found by name
  (packages/layerzero-v2/evm/protocol: EndpointV2; evm/messagelib: SendUln302, ReceiveUln302; plus oapp / oft).
- Recorded by reference only: its root licence is LICENSE-LZBL-1.2 (LayerZero Business Licence, not an open licence),
  and the protocol / messagelib sources carry LZBL-1.2 headers; copy_repo.py did not copy it.
- Left out (not EVM): the Aptos (Move), Solana and TON implementations, and LayerZero-Labs/Audits (reports).
