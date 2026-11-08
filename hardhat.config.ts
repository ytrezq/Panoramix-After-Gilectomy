// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import "dotenv/config";

import "@typechain/hardhat";
import { HardhatUserConfig, HttpNetworkAccountsUserConfig } from "hardhat/types";

import "hardhat-deploy";
import "hardhat-contract-sizer";

import "@layerzerolabs/toolbox-hardhat";
import { EndpointId } from "@layerzerolabs/lz-definitions";

import { getRpcURL } from "./utils/getRpcURL";
import { getVerifyConfig } from "./utils/getVerifyConfig";

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC;

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY;

const accounts: HttpNetworkAccountsUserConfig | undefined = MNEMONIC
  ? { mnemonic: MNEMONIC }
  : PRIVATE_KEY
    ? [PRIVATE_KEY]
    : undefined;

if (accounts == null) {
  console.warn(
    "Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.",
  );
}
const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.25",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ],
  },
  networks: {
    mainnet: {
      eid: EndpointId.ETHEREUM_V2_MAINNET,
      url: getRpcURL("mainnet"),
      accounts,
      verify: getVerifyConfig("mainnet"),
    },
    sepolia: {
      eid: EndpointId.SEPOLIA_V2_TESTNET,
      url: getRpcURL("sepolia"),
      verify: getVerifyConfig("sepolia"),
      accounts,
    },
    polygon: {
      eid: EndpointId.POLYGON_V2_MAINNET,
      url: getRpcURL("polygon"),
      verify: getVerifyConfig("polygon"),
      accounts,
    },
    amoy: {
      eid: EndpointId.AMOY_V2_TESTNET,
      url: getRpcURL("amoy"),
      verify: getVerifyConfig("amoy"),
      accounts,
    },
    arbiSepolia: {
      eid: EndpointId.ARBSEP_V2_TESTNET,
      url: getRpcURL("arbiSepolia"),
      verify: getVerifyConfig("arbiSepolia"),
      accounts,
    },
    fantom: {
      eid: EndpointId.FANTOM_V2_MAINNET,
      url: getRpcURL("fantom"),
      verify: getVerifyConfig("fantom"),
      accounts,
    },
    optimism: {
      eid: EndpointId.OPTIMISM_V2_MAINNET,
      url: getRpcURL("optimism"),
      verify: getVerifyConfig("optimism"),
      accounts,
    },
    base: {
      eid: EndpointId.BASE_V2_MAINNET,
      url: getRpcURL("base"),
      verify: getVerifyConfig("base"),
      accounts,
    },
    arbitrum: {
      eid: EndpointId.ARBITRUM_V2_MAINNET,
      url: getRpcURL("arbitrum"),
      verify: getVerifyConfig("arbitrum"),
      accounts,
    },
    sonic: {
      eid: EndpointId.SONIC_V2_MAINNET,
      url: getRpcURL("sonic"),
      verify: getVerifyConfig("sonic"),
      accounts,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
};
export default config;
