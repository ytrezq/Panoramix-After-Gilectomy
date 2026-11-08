# Gearbox

- Scope: primacy of impact plus Gearbox-protocol/security bug-bounty/v3_1-scope.md, which lists the repositories ("only the
  main or master branch is considered within scope") and paths: permissionless, core-v3, oracles-v3, integrations-v3
  (contracts/ except contracts/test), bots-v3 (contracts/bots), periphery-v3 (contracts/emergency, kyc, migration).
- Copied all 6 at their default branch with those scope paths recorded: permissionless master b1b5e5ba (no repository license:
  copied per file from SPDX headers, 20 unlicensed files skipped), core-v3 main a53223a5 (BUSL-1.1), oracles-v3 main 287739a0,
  integrations-v3 main fefe3aed (BUSL-1.1), bots-v3 main ebec19d2 (GPL-2.0-or-later), periphery-v3 main 2a63cf27 (MIT;
  122 submodules, 71 MB).
- Left out: the older repositories linked from the page (core-v2, integrations-v2, gearbox-contracts, governance): not in the
  v3.1 scope.
- Deployed contracts: the scope file points to AddressProviderV3 and the bytecode repository portal (versions 3_10..3_20);
  not checked one by one.
