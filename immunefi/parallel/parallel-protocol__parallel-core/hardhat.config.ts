import "dotenv/config";

import HardhatNodeTestRunner from "@nomicfoundation/hardhat-node-test-runner";
import HardhatViem from "@nomicfoundation/hardhat-viem";
import HardhatNetworkHelpers from "@nomicfoundation/hardhat-network-helpers";
import HardhatKeystore from "@nomicfoundation/hardhat-keystore";
import HardhatDeploy from "hardhat-deploy";

import { HardhatUserConfig } from "hardhat/types/config";

import { getRpcURL } from "./utils/getRpcURL";

const PRIVATE_KEY = process.env.PRIVATE_KEY;
if (!PRIVATE_KEY) throw new Error("PRIVATE_KEY is not set");
const accounts = [PRIVATE_KEY];

const config: HardhatUserConfig = {
  plugins: [HardhatNodeTestRunner, HardhatViem, HardhatNetworkHelpers, HardhatKeystore, HardhatDeploy],
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10_000,
          },
        },
      },
    ],
  },
  networks: {
    mainnet: {
      type: "http",
      url: getRpcURL("mainnet"),
      accounts,
    },
    sepolia: {
      type: "http",
      url: getRpcURL("sepolia"),
      accounts,
    },
    polygon: {
      type: "http",
      url: getRpcURL("polygon"),
      accounts,
    },
    arbiSepolia: {
      type: "http",
      url: getRpcURL("arbiSepolia"),
      accounts,
    },
    optimism: {
      type: "http",
      url: getRpcURL("optimism"),
      accounts,
    },
    base: {
      type: "http",
      url: getRpcURL("base"),
      accounts,
    },
    arbitrum: {
      type: "http",
      url: getRpcURL("arbitrum"),
      accounts,
    },
    sonic: {
      type: "http",
      url: getRpcURL("sonic"),
      accounts,
    },
    sei: {
      type: "http",
      url: getRpcURL("sei"),
      accounts,
    },
    avalanche: {
      type: "http",
      url: getRpcURL("avalanche"),
      accounts,
    },
    bsc: {
      type: "http",
      url: getRpcURL("bsc"),
      accounts,
    },
    berachain: {
      type: "http",
      url: getRpcURL("berachain"),
      accounts,
    },
    scroll: {
      type: "http",
      url: getRpcURL("scroll"),
      accounts,
    },
    gnosis: {
      type: "http",
      url: getRpcURL("gnosis"),
      accounts,
    },
    unichain: {
      type: "http",
      url: getRpcURL("unichain"),
      accounts,
    },
    ink: {
      type: "http",
      url: getRpcURL("ink"),
      accounts,
    },
    hyperevm: {
      type: "http",
      url: getRpcURL("hyperevm"),
      accounts,
    },
  },
};

export default config;
