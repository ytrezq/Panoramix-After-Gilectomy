import "@nomiclabs/hardhat-solhint";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import { resolve } from "path";
import { config as dotenvConfig } from "dotenv";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "hardhat-docgen";
import "hardhat-gas-reporter";
import { removeConsoleLog } from "hardhat-preprocessor";
import { HardhatUserConfig } from "hardhat/config";
import { NetworkUserConfig } from "hardhat/types";
import "solidity-coverage";
import "hardhat-storage-layout";
import "hardhat-erc1820";
import { DeployParameters } from "./scripts/types";
import "hardhat-storage-layout-diff";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const PCT_BASE = BigInt(1e18);
const DAY_TIME_SPAN = 24n * 60n * 60n;
const WEEK_TIME_SPAN = DAY_TIME_SPAN * 7n;
const MONTH_TIME_SPAN = DAY_TIME_SPAN * 30n;

declare module "hardhat/types/config" {
  export interface HardhatNetworkUserConfig {
    deployParameters: DeployParameters;
  }
  export interface HardhatNetworkConfig {
    deployParameters: DeployParameters;
  }
  export interface HttpNetworkConfig {
    deployParameters: DeployParameters;
  }
}

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
  rskTestnet: 31,
};

// Ensure that we have all the environment variables we need.
let mnemonic: string;
if (!process.env.MNEMONIC) {
  throw new Error("Please set your MNEMONIC in a .env file");
} else {
  mnemonic = process.env.MNEMONIC;
}

let infuraApiKey: string;
if (!process.env.INFURA_API_KEY) {
  throw new Error("Please set your INFURA_API_KEY in a .env file");
} else {
  infuraApiKey = process.env.INFURA_API_KEY;
}

const createTestnetConfig = (network: keyof typeof chainIds): NetworkUserConfig => {
  const url: string = "https://" + network + ".infura.io/v3/" + infuraApiKey;
  return {
    accounts: {
      count: 10,
      initialIndex: 0,
      mnemonic,
      path: "m/44'/60'/0'/0",
    },
    chainId: chainIds[network],
    url,
  };
};

const baseDeployParams = {
  coreParams: {
    protThrld: PCT_BASE * 2n, // 2
    liqThrld: (PCT_BASE * 104n) / 100n, // 1.04
    emaCalculationTimeSpan: DAY_TIME_SPAN,
    successFee: PCT_BASE / 10n, // 10%
    appreciationFactor: PCT_BASE / 2n, // 50%
    tcInterestRate: (PCT_BASE * 5n) / 100000n, // 0.005% : weekly 0.0025 / 365 * 7
    tcInterestPaymentTimeSpan: WEEK_TIME_SPAN,
    decayTimeSpan: DAY_TIME_SPAN,
    transferMaxGas: 3000n,
    allowDifferentRecipient: true,
  },
  settlementParams: {
    settlementTimeSpan: MONTH_TIME_SPAN,
  },
  vendorsParams: {
    maxMarkup: PCT_BASE / 10n, // 10%
  },
  feeParams: {
    feeRetainer: 0n, // 0%
    tcMintFee: (PCT_BASE * 5n) / 100n, // 5%
    tcRedeemFee: (PCT_BASE * 5n) / 100n, // 5%
    swapTPforTPFee: (PCT_BASE * 1n) / 100n, // 1%
    swapTPforTCFee: (PCT_BASE * 1n) / 100n, // 1%
    swapTCforTPFee: (PCT_BASE * 1n) / 100n, // 1%
    redeemTCandTPFee: (PCT_BASE * 8n) / 100n, // 8%
    mintTCandTPFee: (PCT_BASE * 8n) / 100n, // 8%
    feeTokenPct: PCT_BASE / 2n, // 50%
  },
  ctParams: {
    name: "CollateralToken",
    symbol: "CT",
    decimals: 18n,
  },
  mocAddresses: {
    governorAddress: "", // if not provided a new GovernorMock.sol is deployed
    pauserAddress: "0x26a00aF444928D689DDec7B4D17C0e4a8c9d407b",
    feeTokenAddress: "0x26a00AF444928d689DDeC7b4d17c0e4A8c9D4060",
    feeTokenPriceProviderAddress: "0x26A00AF444928d689ddec7b4d17c0E4A8C9D4061",
    mocFeeFlowAddress: "0x26a00aF444928d689DDEC7b4D17c0E4a8c9D407d",
    mocAppreciationBeneficiaryAddress: "0x26A00aF444928D689ddEC7B4D17C0E4A8C9d407F",
    vendorsGuardianAddress: "0x26a00AF444928D689DDeC7b4D17c0E4a8C9d407E",
    tcInterestCollectorAddress: "0x27a00Af444928D689DDec7B4D17c0E4a8c9d407F",
    maxAbsoluteOpProviderAddress: "0x26A00AF444928d689ddec7b4d17c0E4A8C9D4061",
    maxOpDiffProviderAddress: "0x26A00AF444928d689ddec7b4d17c0E4A8C9D4061",
  },
  queueParams: {
    minOperWaitingBlk: 1n,
    maxOperWaitingBlk: 2n,
    execCostParams: {
      tcMintExecCost: 1000000n,
      tcRedeemExecCost: 1000001n,
      tpMintExecCost: 1000002n,
      tpRedeemExecCost: 1000003n,
      mintTCandTPExecCost: 2000000n,
      redeemTCandTPExecCost: 2000001n,
      swapTPforTPExecCost: 2000002n,
      swapTPforTCExecCost: 1000003n,
      swapTCforTPExecCost: 1000004n,
    },
  },
  multiCollateralParams: {
    maxOperPerBatch: 15n,
    useMaxLastPublicationBlock: true,
    microLiquidationExecCost: PCT_BASE / 100n, // 0.01 ether
    liquidationExecCost: PCT_BASE / 10n, // 0.1 ether
    coinbaseExecFeeRecipient: "0x28A00Af444928D689ddEC7B4D17c0e4a8c9d4061",
  },
  liquidationParams: {
    acCoinbasePriceProviderAddress: "",
    rtcThrld: (PCT_BASE * 18n) / 10n, // 1.8
    microLiquidationThrld: (PCT_BASE * 13n) / 10n, // 1.3
    penaltyRate: (PCT_BASE * 7n) / 1000n, // 0.7%
    mocSwappers: [], // empty because is the first bucket
  },
  gasLimit: 30000000, // high value to avoid coverage issue. https://github.com/NomicFoundation/hardhat/issues/3121
};

const localDeployParams = {
  ...baseDeployParams,
  tpParams: {
    tpParams: [
      {
        name: "tUSD",
        symbol: "tUSD",
        decimals: 18n,
        priceProvider: "", // if not provided a new FakePriceProvider with price = 1 will be deployed
        tpCtarg: (PCT_BASE * 55n) / 10n, // 5.5
        tpMintFee: PCT_BASE / 100n, // 1%
        tpRedeemFee: PCT_BASE / 100n, // 1%
        tpEma: (PCT_BASE * 6790n) / 100000n, //0.06790
        tpEmaSf: (PCT_BASE * 1104n) / 100000n, // 0.01104
      },
    ],
  },
};

const rskDeployParams = {
  ...localDeployParams,
  ...{ gasLimit: 6800000 },
};

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: 0,
    otherUser: 1,
    alice: 2,
    bob: 3,
    charlie: 4,
    vendor: 5,
    pauser: 6,
    executor: 7,
  },
  networks: {
    hardhat: {
      accounts: {
        mnemonic,
        accountsBalance: "100000000000000000000000000000000000",
      },
      chainId: chainIds.hardhat,
      gasPrice: 0,
      initialBaseFeePerGas: 0,
      allowUnlimitedContractSize: true, // TODO: remove this
      deployParameters: baseDeployParams,
      tags: ["testing"],
    },
    localhost: {
      accounts: {
        mnemonic,
        accountsBalance: "100000000000000000000000000000000000",
      },
      chainId: chainIds.hardhat,
      gasPrice: 0,
      initialBaseFeePerGas: 0,
      allowUnlimitedContractSize: true, // TODO: remove this
      deployParameters: localDeployParams,
      tags: ["testing"],
    },
    rskTestnetDev: {
      accounts: process.env.PK ? [`0x${process.env.PK}`] : { mnemonic },
      chainId: chainIds.rskTestnet,
      url: process.env["RSK_TESTNET_RPC"] || "https://public-node.testnet.rsk.co",
      deployParameters: rskDeployParams,
      tags: ["testing"],
    },
    goerli: { ...createTestnetConfig("goerli"), deployParameters: rskDeployParams, tags: ["testing"] },
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    version: "0.8.24",
    settings: {
      // https://hardhat.org/hardhat-network/#solidity-optimizer-support
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yulDetails: {
            // solves viaIR issue that inline internal functions: https://github.com/ethereum/solidity/issues/13858#issuecomment-1428754261
            optimizerSteps:
              "dhfoDgvulfnTUtnIf[xa[r]EscLMcCTUtTOntnfDIulLculVcul[j]Tpeulxa[rul]xa[r]cLgvifCTUca[r]LSsTOtfDnca[r]Iulc]jmul[jul]VcTOculjmul",
          },
        },
      },
      viaIR: process.env.VIA_IR === undefined ? true : process.env.VIA_IR == "true",
      evmVersion: "paris",
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v6",
    alwaysGenerateOverloads: false,
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: "USD",
    gasPrice: 21,
  },
  preprocess: {
    eachLine: removeConsoleLog(hre => !["hardhat", "localhost"].includes(hre.network.name)),
  },
  docgen: {
    path: "./docs",
    clear: false,
    runOnCompile: false,
    except: ["^contracts/mocks/"],
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
    except: ["^contracts/mocks/"],
  },
  mocha: {
    timeout: 1000000,
  },
};

export default config;
