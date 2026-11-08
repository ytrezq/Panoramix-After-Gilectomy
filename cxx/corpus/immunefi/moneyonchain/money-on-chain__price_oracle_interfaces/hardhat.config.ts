// hardhat.config.js (ESM)
//import 'dotenv/config';
import ethersPlugin from "@nomicfoundation/hardhat-ethers";
import mochaPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import verifyPlugin from "@nomicfoundation/hardhat-verify";
import { configVariable } from "hardhat/config";

import ignitionPlugin from "@nomicfoundation/hardhat-ignition-ethers";
import helpersPlugin from "@nomicfoundation/hardhat-network-helpers";
import typechainPlugin from "@nomicfoundation/hardhat-typechain";
import { config as dotenvConfig } from "dotenv";

dotenvConfig();

export default {
  plugins: [
    ethersPlugin,
    typechainPlugin,
    mochaPlugin,
    verifyPlugin,
    ignitionPlugin,
    helpersPlugin,
  ],
  test: {
    files: ["./test/**/*.spec.ts", "./test/**/*.test.ts"],
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
      {
        version: "0.7.6",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
    ],
  },
  networks: {
    // Red local/embebida (opcional)
    hardhat: {
      type: "edr-simulated",
      forking: {
        url: process.env.FORK_URL ?? configVariable("FORK_URL"), // <- needit
        blockNumber: process.env.FORK_BLOCK ? Number(process.env.FORK_BLOCK) : undefined,
        // headers y timeout optional if you use a public RPC that sometimes delays:
        // httpHeaders: { /* ... */ },
        // timeout: 120000,
      },
    },

    // RSK Testnet (HTTP RPC)
    rskAlphaTestnet: {
      type: "http",
      url: process.env.RPC_URL_RSK_TESTNET ?? "https://public-node.testnet.rsk.co",
      chainId: 31,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      // gasPrice: 60000000n, // optional (wei)
    },

    // RSK Testnet (HTTP RPC)
    rskTestnet: {
      type: "http",
      url: process.env.RPC_URL_RSK_TESTNET ?? "https://public-node.testnet.rsk.co",
      chainId: 31,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      // gasPrice: 60000000n, // optional (wei)
    },

    // RSK Mainnet (HTTP RPC)
    rskMainnet: {
      type: "http",
      url: process.env.RPC_URL_RSK_MAINNET ?? "https://public-node.rsk.co",
      chainId: 30,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  // ✅ En HH3 use verify
  verify: {
    // Ignition verifies through the Etherscan-compatible Rootstock Explorer API.
    // The API requires a non-empty key but does not authenticate it.
    etherscan: { enabled: true, apiKey: "rootstock" },
    blockscout: { enabled: true },
  },
  chainDescriptors: {
    31: {
      name: "Rootstock Testnet",
      blockExplorers: {
        etherscan: {
          name: "Rootstock Testnet Explorer",
          url: "https://explorer.testnet.rootstock.io",
          apiUrl: "https://be.explorer.testnet.rootstock.io/api/v3/etherscan",
        },
        blockscout: {
          name: "Rootstock Testnet Blockscout",
          url: "https://rootstock-testnet.blockscout.com",
          apiUrl: "https://rootstock-testnet.blockscout.com/api",
        },
      },
    },
    30: {
      name: "Rootstock Mainnet",
      hardforkHistory: { shanghai: { blockNumber: 0 } },
      blockExplorers: {
        etherscan: {
          name: "Rootstock Explorer",
          url: "https://explorer.rootstock.io",
          apiUrl: "https://be.explorer.rootstock.io/api/v3/etherscan",
        },
        blockscout: {
          name: "Rootstock Blockscout",
          url: "https://rootstock.blockscout.com",
          apiUrl: "https://rootstock.blockscout.com/api",
        },
      },
    },
  },
};
