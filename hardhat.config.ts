import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
// import "@nomicfoundation/hardhat-foundry";

require("hardhat-contract-sizer"); // "npx hardhat size-contracts" or "yarn run hardhat size-contracts"

dotenv.config();

import "./tasks/swap-amounts";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.21",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "paris",
      remappings: [
        "ds-test/=lib/forge-std/lib/ds-test/src/",
        "eth-gas-reporter/=eth-gas-reporter/",
        "forge-std/=lib/forge-std/src/",
        "hardhat/=hardhat/",
      ]
    },
  },
  networks: {
    mainnet: {
      url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_MAINNET_API_KEY}`,
      accounts: {
        mnemonic: process.env.MAINNET_MNEMONIC || "",
      },
      chainId: 1,
    },
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_SEPOLIA_API_KEY}`,
      accounts: {
        mnemonic: process.env.SEPOLIA_MNEMONIC || "",
      },
      chainId: 11155111,
    },
    arbitrumGoerli: {
      url: `https://arb-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_ARBITRUM_GOERLI_API_KEY}`,
      accounts: {
        mnemonic:
            process.env.ARBITRUM_GOERLI_MNEMONIC ||
            "female like problem scare over lizard client bonus pioneer submit myth collect",
        path: "m/44'/60'/0'/0",
      },
      chainId: 421613,
    },
    arbitrumSepolia: {
      url: `https://arb-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_ARBITRUM_SEPOLIA_API_KEY}`,
      accounts: {
        mnemonic: process.env.ARBITRUM_SEPOLIA_MNEMONIC || "",
      },
      chainId: 421614,
    },
    arbitrum: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_ARBITRUM_API_KEY}`,
      accounts: {
        mnemonic:
            process.env.ARBITRUM_MNEMONIC ||
            "female like problem scare over lizard client bonus pioneer submit myth collect",
        path: "m/44'/60'/0'/0",
      },
      chainId: 42161,
    },
    base: {
      url: `https://base-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_BASE_API_KEY}`,
      accounts: {
        mnemonic: process.env.BASE_MNEMONIC || "",
      },
      chainId: 8453,
    },
    baseSepolia: {
      url: `https://base-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_BASE_SEPOLIA_API_KEY}`,
      accounts: {
        mnemonic: process.env.BASE_SEPOLIA_MNEMONIC || "",
      },
      chainId: 84532,
    },
    sonic: {
      url: `https://sonic-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_SONIC_API_KEY}`,
      accounts: {
        mnemonic: process.env.SONIC_MNEMONIC || "",
      },
      chainId: 146,
    },
    sonicTestnet: {
      url: `https://sonic-blaze.g.alchemy.com/v2/${process.env.ALCHEMY_SONIC_BLAZE_API_KEY}`,
      accounts: {
        mnemonic: process.env.SONIC_BLAZE_MNEMONIC || "",
      },
      chainId: 57054,
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
    customChains: [
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io",
        },
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org/",
        },
      },
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia-explorer.base.org/",
        },
      },
      {
        network: "sonic",
        chainId: 146,
        urls: {
          apiURL: "https://api.sonicscan.org/api",
          browserURL: "https://sonicscan.org",
        },
      },
      {
        network: "sonicTestnet",
        chainId: 57054,
        urls: {
          apiURL: "https://api-testnet.sonicscan.org/api",
          browserURL: "https://testnet.sonicscan.org",
        },
      },
    ],
  },
};

export default config;
