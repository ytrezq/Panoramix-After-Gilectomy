import { HardhatUserConfig } from "hardhat/config";
import type { HttpNetworkAccountsUserConfig } from "hardhat/types/config";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { config as dotenvConfig } from "dotenv";
import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import hardhatContractSizer from "@solidstate/hardhat-contract-sizer";
import "@nomicfoundation/hardhat-verify";

// Note: @nomicfoundation/hardhat-toolbox-mocha-ethers includes:
// - @nomicfoundation/hardhat-ethers
// - @nomicfoundation/hardhat-ethers-chai-matchers
// - @nomicfoundation/hardhat-ignition
// - @nomicfoundation/hardhat-ignition-ethers
// - @nomicfoundation/hardhat-keystore
// - @nomicfoundation/hardhat-mocha
// - @nomicfoundation/hardhat-network-helpers
// - @nomicfoundation/hardhat-typechain
// - @nomicfoundation/hardhat-verify

// ESM equivalent of __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

dotenvConfig({ path: resolve(__dirname, "./.env") });

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  mainnet: 1,
  rskTestnet: 31,
  rskMainnet: 30,
};

const pk = process.env.PK?.trim();
const mnemonic = process.env.MNEMONIC?.trim();

if (!pk && !mnemonic) {
  throw new Error("Please set PK or MNEMONIC in a .env file");
}

const accounts: HttpNetworkAccountsUserConfig = pk ? [pk] : { mnemonic: mnemonic! };

const testnet_rpc_url = process.env["RSK_TESTNET_RPC_URL"] || "https://public-node.testnet.rsk.co";
const mainnet_rpc_url = process.env["RSK_MAINNET_RPC_URL"] || "https://public-node.rsk.co";

const compilers = [
  {
    version: "0.5.8",
    settings: { optimizer: { enabled: true, runs: 200 } },
  },
  {
    version: "0.6.12",
    settings: { optimizer: { enabled: true, runs: 200 } },
  },
  {
    version: "0.7.6",
    settings: { optimizer: { enabled: true, runs: 200 } },
  },
  {
    version: "0.8.16",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "london",
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yulDetails: {
            optimizerSteps:
              "dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul[j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul]VcTOculjmul",
          },
        },
      },
      viaIR: true,
      evmVersion: "london",
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yulDetails: {
            optimizerSteps:
              "dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul[j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul]VcTOculjmul",
          },
        },
      },
      viaIR: true,
      evmVersion: "london",
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
];

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxMochaEthers, hardhatContractSizer],

  solidity: {
    profiles: {
      production: {
        isolated: false,
        compilers,
      },
      default: {
        compilers,
      },
    },
    npmFilesToBuild: [
      "moc-main-latest/contracts/collateral/rc20/MocCARC20.sol",
      "moc-main-latest/contracts/core/MocCoreExpansion.sol",
      "moc-main-latest/contracts/mocks/PriceProviderMock.sol",
      "moc-main-latest/contracts/auxiliary/CommissionSplitterRC20.sol",
      "moc-main-latest/contracts/governance/InterimGovernor.sol",
      "moc-main-latest/contracts/tokens/MocRC20.sol",
      "moc-main-latest/contracts/queue/MocQueue.sol",
      "moc-main-latest/contracts/multiCollateral/MocMultiCollateralGuard.sol",

      "moc-main-latest/contracts/auxiliary/MocReverseAuction.sol",
      "moc-main-latest/contracts/multiCollateral/swapper/MocSwapperV3.sol",
      "moc-main-latest/contracts/multiCollateral/swapper/MocSwapperV3MultiHop.sol",

      "@moc/price-oracle-interfaces/contracts/PriceProviderInverse.sol",
      "@moc/price-oracle-interfaces/contracts/PriceProviderDummy.sol",
      "@moc/price-oracle-interfaces/contracts/PriceProviderDocRbtc.sol",
      "@moc/price-oracle-interfaces/contracts/PriceProviderDocUsd.sol",
      "@moc/price-oracle-interfaces/contracts/PriceProviderDiv.sol",

      "@moc/flow/contracts/BufferToken.sol",

      "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol",
    ],
  },
  contractSizer: {
    runOnCompile: true,
    except: [/.*[Tt]ests?$/, /.*[Mm]ock.*/, /.*Handler$/, /.*\.t\.sol/],
    flat: false,
  },
  verify: {
    // Rootstock explorer is still experimental
    // as it needs extra parameters obtained from the website
    // to interact with the nextjs app.
    rootstockExplorer: {
      enabled: false,
    },
    blockscout: {
      enabled: true,
    },
    etherscan: {
      enabled: false,
      apiKey: process.env.ETHERSCAN_API_KEY ?? "unused",
    },
  },
  chainDescriptors: {
    [chainIds.rskMainnet]: {
      name: "Rootstock",
      chainType: "generic",
      blockExplorers: {
        etherscan: {
          url: "",
          apiUrl: "",
        },
        blockscout: {
          url: "https://rootstock.blockscout.com",
          apiUrl: "https://rootstock.blockscout.com/api",
        },
        rootstockExplorer: {
          name: "Rootstock.io",
          url: "https://explorer.rootstock.io",
          apiUrl: "https://explorer.rootstock.io",
        },
      },
    },
    [chainIds.rskTestnet]: {
      name: "Rootstock Testnet",
      chainType: "generic",
      blockExplorers: {
        etherscan: {
          url: "",
          apiUrl: "",
        },
        blockscout: {
          url: "https://rootstock-testnet.blockscout.com",
          apiUrl: "https://rootstock-testnet.blockscout.com/api",
        },
        rootstockExplorer: {
          name: "Rootstock.io Testnet",
          url: "https://explorer.testnet.rootstock.io",
          apiUrl: "https://explorer.testnet.rootstock.io",
        },
      },
    },
  },
  networks: {
    hardhat: {
      type: "edr-simulated",
      chainId: chainIds.hardhat,
      accounts: {
        mnemonic: mnemonic!,
        accountsBalance: 1000000000n,
      },
    },
    rskAlphaTestnet: {
      type: "http",
      url: testnet_rpc_url,
      chainId: chainIds.rskTestnet,
      accounts,
    },
    rskTestnet: {
      type: "http",
      url: testnet_rpc_url,
      chainId: chainIds.rskTestnet,
      accounts,
    },
    rskMainnet: {
      type: "http",
      url: mainnet_rpc_url,
      chainId: chainIds.rskMainnet,
      accounts,
    },
    rskMainnetFork: {
      type: "edr-simulated",
      forking: {
        url: "https://public-node.rsk.co",
        blockNumber: 8524500,
      },
      chainId: 30,
      accounts: {
        mnemonic: mnemonic!,
        accountsBalance: 10000000000000000000n,
      },
      //loggingEnabled: true,
    },
    localhost: {
      type: "http",
      url: "http://localhost:8545",
      chainId: chainIds.rskMainnet,
      accounts,
      gas: 30000000,
    },
  },
  ignition: {
    blockPollingInterval: 5000,
    timeBeforeBumpingFees: 120000,
    maxFeeBumps: 10,
    requiredConfirmations: 1,
    maxUnconfirmedTxs: 1,
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },

  test: {
    solidity: {
      ffi: true,
      fsPermissions: {
        readDirectory: ["./out", "./test", "./ignition/deployments"],
      },
    },
  },

  typechain: {
    outDir: "./typechain",
  },
};

export default config;
