# Aera (aera)

- Scope: 29 addresses of Aera v3 vaults on Ethereum, Base, Arbitrum, Optimism and Morph (gtUSDa, gtBTC, gpAAFalconX, bgBTC): MultiDepositorVault, Provisioner, PriceAndFeeCalculator, Whitelist, TransferBlacklistHook. No repository is linked in the scope.
- Copied: aera-finance/aera-contracts-public (linked on the page for its audits) at 3b1477c, scope v3: the last commit before the "provisioner v2" upgrade (2026-07-16), whose v3/src/core/Provisioner.sol and PriceAndFeeCalculator.sol are the contracts Sourcify verifies for gtUSDa on Ethereum (solc 0.8.29); the default branch now holds ProvisionerV2/PriceAndFeeCalculatorV2 instead.
- The repository is a source mirror: no build configuration and no dependencies (its imports use @oz = OpenZeppelin 5.x and @solmate remappings it does not define).
- Not covered: TransferBlacklistHook (4 addresses): not in the public repository (only the IBeforeTransferHook interface).
