## Runing Tests

- Copy .example.env to your own .env
- Use your preferred RPC urls or the default
- run "source .env"
- forge test

### Note

Integration tests and the AlchemistETHVault test are targetting mainnet by default.
Run with you preferred mainnet RPC URL :

- FOUNDRY_PROFILE=default forge test --fork-url https://mainnet.gateway.tenderly.co --match-path src/test/IntegrationTest.t.sol -vvvv --evm-version cancun

- FOUNDRY_PROFILE=default forge test --fork-url https://mainnet.gateway.tenderly.co --match-path src/test/AlchemistETHVault.t.sol -vvvv --evm-version cancun
