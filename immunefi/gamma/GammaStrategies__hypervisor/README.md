## Hypervisor

###
A Uniswap V2-like interface with fungible liquidity to Uniswap V3
which allows for arbitrary liquidity provision: one-sided, lop-sided, and
balanced

Consult tests/hypervisor.test.ts for deposit, withdrawal, rebalance examples

### Tasks

Deploys hypervisor factory

`npx hardhat deploy-hypervisor-factory --network NETWORK`

Deploys hypervisor with factory

`npx hardhat deploy-hypervisor-orphan --token0 ERC20-ADDRESS --token1 ERC20-ADDRESS --fee POOL-FEE("LOW", "MEDIUM", "HIGH") --name ERC20-NAME --symbol ERC20-SYMBOL --network NETWORK`

Deploys hypervisor without factory

`npx hardhat deploy-hypervisor-orphan --pool UNIV3-POOL-ADDRESS --name ERC20-NAME --symbol ERC20-SYMBOL --network NETWORK`

### Testing

`npx hardhat test`
