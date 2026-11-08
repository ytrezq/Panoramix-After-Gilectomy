# paxos-labs

- Scope: 15 smart-contract assets, Ethereum addresses of two BoringVault deployments: PAXGy (BoringVault token,
  Accountant, Teller, Manager, RolesAuthority, WithdrawQueue and its fee module, DCD fee module,
  DistributorCodeDepositor, FreezeListBeforeTransferHook) and Transit (BoringVault, Manager, Decoder,
  RolesAuthority, TransitStation).
- No in-scope repository link; the page links paxoslabs/pxl-boring-vault @ master (for an audit PDF).
- Copied: paxoslabs/pxl-boring-vault @ master (default branch): Paxos Labs' fork of Veda's BoringVault (src/base:
  BoringVault, Roles, Accountant, Teller, Manager, decoders and sanitizers, WithdrawQueue, fee modules,
  DistributorCodeDepositor, FreezeListBeforeTransferHook, TransitStation...), with its lib/ submodules
  (OpenZeppelin, solmate, ion-protocol, predicate-contracts, createx, aave-v3-core, LayerZero devtools...) and npm
  packages: the biggest copy of this list (11,494 files, 66 MB).
- No licence file and no package.json licence: copy_repo.py copied the sources whose own SPDX header is open and
  skipped 20 (UNLICENSED or header-less; manifest skipped_unlicensed). Every scope name matched a contract here.
