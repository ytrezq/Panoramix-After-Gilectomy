import { HardhatUserConfig, vars } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@openzeppelin/hardhat-upgrades';
import '@nomicfoundation/hardhat-ethers';
import 'hardhat-gas-reporter';
import 'hardhat-deploy';

import './scripts';
import './tasks';

const config: HardhatUserConfig = {
  gasReporter: {
    enabled: true,
    currency: 'USD',
    L1: 'ethereum',
    coinmarketcap: vars.get('CMC_API_KEY', ''),
    L1Etherscan: vars.get('ETHERSCAN_API_KEY', '')
  },
  solidity: {
    compilers: [
      {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  networks: {
    // testnets
    holesky: {
      loggingEnabled: true,
      url: vars.get('HOLESKY_RPC', 'https://ethereum-holesky-rpc.publicnode.com'),
      chainId: 17_000,
      accounts: [vars.get('TESTNET_DEPLOYER_SK', '0x0000000000000000000000000000000000000000000000000000000000000001')],
      gas: 8_000_000,
      gasMultiplier: 1.5,
      timeout: 180_000
    },
    sepolia: {
      loggingEnabled: true,
      url: vars.get('SEPOLIA_RPC', 'https://ethereum-sepolia-rpc.publicnode.com'),
      chainId: 11155111,
      accounts: [vars.get('TESTNET_DEPLOYER_SK', '0x0000000000000000000000000000000000000000000000000000000000000001')],
      gas: 8_000_000,
      gasMultiplier: 1.1,
      timeout: 180_000
    },
    // mainnets
    mainnet: {
      loggingEnabled: true,
      url: vars.get('MAINNET_RPC', 'https://ethereum-rpc.publicnode.com'),
      chainId: 1,
      accounts: [vars.get('DEPLOYER_SK', '0x0000000000000000000000000000000000000000000000000000000000000001')],
      timeout: 90_000,
      gas: 8_000_000,
      gasMultiplier: 1
    }
  },
  etherscan: {
    customChains: [],
    apiKey: {
      // testnets
      holesky: vars.get('ETHERSCAN_API_KEY', ''),
      sepolia: vars.get('ETHERSCAN_API_KEY', ''),
      // mainnets
      mainnet: vars.get('ETHERSCAN_API_KEY', '')
    }
  },
  sourcify: {
    enabled: false
  }
};

export default config;
