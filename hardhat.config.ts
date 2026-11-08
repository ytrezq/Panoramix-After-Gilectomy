import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-deploy";

require("hardhat-contract-sizer"); // "npx hardhat size-contracts" or "yarn run hardhat size-contracts"

dotenv.config({ path: __dirname + '/.env'});

// This is a sample Hardhat tasks. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

import "./tasks/bridge";
import "./tasks/lz-config";
import "./tasks/lz-gen-config";
import "./tasks/lz-set-config";
import "./tasks/lz-set-delegate";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.22",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
      allowUnlimitedContractSize: true
    },
    localhost: {
      chainId: 31337,
      allowUnlimitedContractSize: true
    },
    mainnet: {
      url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_MAINNET_API_KEY}`,
      accounts: {
        mnemonic: process.env.MAINNET_MNEMONIC || "",
      },
      chainId: 1,
    },
    arbitrum: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_ARBITRUM_API_KEY}`,
      accounts: {
        mnemonic: process.env.ARBITRUM_MNEMONIC || "",
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
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_SEPOLIA_API_KEY}`,
      accounts: {
        mnemonic: process.env.SEPOLIA_MNEMONIC || "",
      },
      chainId: 11155111,
    },
    arbitrumSepolia: {
      url: `https://arb-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_ARBITRUM_SEPOLIA_API_KEY}`,
      accounts: {
        mnemonic: process.env.ARBITRUM_SEPOLIA_MNEMONIC || "",
      },
      chainId: 421614,
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
      chainId: 146,
      accounts: {
        mnemonic: process.env.SONIC_MNEMONIC || "",
      }
    },
    sonicTestnet: {
      chainId: 57054,
      url: `https://sonic-blaze.g.alchemy.com/v2/${process.env.ALCHEMY_SONIC_BLAZE_API_KEY}`,
      accounts: {
        mnemonic: process.env.SONIC_BLAZE_MNEMONIC || "",
      },
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
          browserURL: "https://sonicscan.org"
        }
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
  namedAccounts: {
    deployer: {
      default: 10, // here this will by default take the first account as deployer
      1: 10,  // similarly on mainnet it will take the first account as deployer. Note though that depending on how hardhat network are configured, the account 0 on one network can be different than on another
    },
    user0: {
      default: 0, // here this will by default take the first account as deployer
      1: 0, // similarly on mainnet it will take the first account as deployer. Note though that depending on how hardhat network are configured, the account 0 on one network can be different than on another
    },
    user1: {
      default: 1, // here this will by default take the first account as deployer
      1: 1, // similarly on mainnet it will take the first account as deployer. Note though that depending on how hardhat network are configured, the account 0 on one network can be different than on another
    },
    user2: {
      default: 2, // here this will by default take the first account as deployer
      1: 2, // similarly on mainnet it will take the first account as deployer. Note though that depending on how hardhat network are configured, the account 0 on one network can be different than on another
    },
  }
};

export default config;
