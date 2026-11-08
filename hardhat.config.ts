/* eslint @typescript-eslint/no-non-null-assertion: ["off"] */

import { HardhatUserConfig } from "hardhat/config";
import type { MultiSolcUserConfig } from "hardhat/src/types/config";
// import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";
/* Uncomment if support of TypeScript `paths` mappings is needed.
 * Make sure to run `pnpm add -D "tsconfig-paths@4.2.0"` in this case.
 */
// import "tsconfig-paths/register";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
/* `hardhat-tracer` traces events, calls and storage operations as tests progress.
 * However, it slows down test execution even when not in use. It can be commented out if it is not needed.
 */
import "hardhat-tracer";
import "solidity-docgen"; // The tool by OpenZeppelin to generate documentation for contracts in Markdown.
import "hardhat-contract-sizer";
import "hardhat-abi-exporter";
// import "hardhat-exposed";

import dotenv from "dotenv";
dotenv.config();

import "./scripts/tasks/generate-account";

const envs = process.env;
const ANKR_KEY = envs.ANKR_KEY ?? "";
const UNICHAIN_QUICKNODE_KEY = envs.UNICHAIN_QUICKNODE_KEY ?? "";

// Private keys can be set in `.env` file.
const ethereumMainnetKeys = envs.ETHEREUM_MAINNET_KEYS?.split(",") ?? [];
// const ethereumTestnetKeys = envs.ETHEREUM_TESTNET_KEYS?.split(",") ?? [];

const isOptionTrue = (option: string | undefined) => ["true", "1"].includes(option ?? "");

/* The solc compiler optimizer is disabled by default to keep the Hardhat stack traces' line numbers the same.
 * To enable, set `RUN_OPTIMIZER` to `true` in the `.env` file.
 */
const optimizerRuns = isOptionTrue(envs.RUN_OPTIMIZER) || isOptionTrue(envs.REPORT_GAS);
const optimizerRunNum = envs.OPTIMIZER_RUN_NUM ? +envs.OPTIMIZER_RUN_NUM : 200;
const viaIR = envs.VIA_IR ? isOptionTrue(envs.VIA_IR) : true;

const enableForking = isOptionTrue(envs.FORKING);

const mochaSerial = isOptionTrue(envs.SERIAL);
const mochaBail = isOptionTrue(envs.BAIL);

const enableSourcify = envs.SOURCIFY ? true : envs.ETHERSCAN_API_KEY ? false : true;

const abiExporterExceptions = ["interfaces/", "mocks/", "vendor/", "contracts-exposed/"];

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.29",
                settings: {
                    viaIR: viaIR,
                    optimizer: {
                        enabled: optimizerRuns,
                        runs: optimizerRunNum,
                        details: {
                            yulDetails: {
                                optimizerSteps: optimizerRuns ? "u" : undefined
                            }
                        }
                    }
                }
            },
            {
                version: "0.8.15",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1,
                        details: {
                            yulDetails: {
                                optimizerSteps:
                                    "dhfoDgvulfnTUtnIf [xa[r]scLM cCTUtTOntnfDIul Lcul Vcul [j] Tpeul xa[rul] xa[r]cL gvif CTUca[r]LsTOtfDnca[r]Iulc] jmul[jul] VcTOcul jmul"
                            }
                        }
                    },
                    outputSelection: {
                        "*": {
                            "*": ["evm.deployedBytecode.sourceMap"]
                        }
                    },
                    viaIR: true
                }
            }
        ]
        // overrides: { "contracts/Deployed.sol": { version: "0.8.21" } }
    },
    // defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            gasPrice: 100_000_000_000,
            allowUnlimitedContractSize: !optimizerRuns,
            accounts: {
                accountsBalance: envs.ACCOUNT_BALANCE ?? "10000000000000000000000", // 10000 ETH.
                count: envs.NUMBER_OF_ACCOUNTS ? +envs.NUMBER_OF_ACCOUNTS : 20
            },
            forking: {
                url: envs.FORKING_URL ?? "",
                enabled: enableForking
            }
            // Uncomment if "Error: cannot estimate gas; transaction may fail or may require manual gas limit...".
            // gas: 3E7,
            // gasPrice: 8E9
        },
        ethereum: {
            chainId: 1,
            url: `https://rpc.ankr.com/eth/${ANKR_KEY}`,
            accounts: [...ethereumMainnetKeys]
        },
        sepolia: {
            chainId: 11155111,
            url: `https://rpc.ankr.com/eth_sepolia/${ANKR_KEY}`,
            accounts: [...ethereumMainnetKeys]
        },
        ronin: {
            chainId: 2020,
            url: "https://ronin.lgns.net/rpc",
            accounts: [...ethereumMainnetKeys]
        },
        polygon: {
            chainId: 137,
            url: `https://rpc.ankr.com/polygon/${ANKR_KEY}`,
            accounts: [...ethereumMainnetKeys]
        },
        optimism: {
            chainId: 10,
            url: `https://rpc.ankr.com/optimism/${ANKR_KEY}`,
            accounts: [...ethereumMainnetKeys]
        },
        mantle: {
            chainId: 5000,
            url: `https://rpc.ankr.com/mantle/${ANKR_KEY}`,
            accounts: [...ethereumMainnetKeys]
        },
        unichain: {
            chainId: 130,
            url: `https://multi-boldest-patina.unichain-mainnet.quiknode.pro/${UNICHAIN_QUICKNODE_KEY}`,
            accounts: [...ethereumMainnetKeys]
        },
        base: {
            chainId: 8453,
            url: `https://rpc.ankr.com/base/${ANKR_KEY}`,
            accounts: [...ethereumMainnetKeys]
        },
        arbitrum: {
            chainId: 42161,
            url: `https://rpc.ankr.com/arbitrum/${ANKR_KEY}`,
            accounts: [...ethereumMainnetKeys]
        },
        avalanche: {
            chainId: 43114,
            url: "https://api.avax.network/ext/bc/C/rpc",
            accounts: [...ethereumMainnetKeys]
        },
        fuji: {
            chainId: 43113,
            url: "https://api.avax-test.network/ext/bc/C/rpc",
            accounts: [...ethereumMainnetKeys]
        },
        scroll: {
            chainId: 534352,
            url: "https://rpc.scroll.io",
            accounts: [...ethereumMainnetKeys]
        }
    },
    etherscan: {
        // To see supported networks and their identifiers for `apiKey`, run `pnpm hardhat verify --list-networks`.
        apiKey: {
            mainnet: envs.ETHERSCAN_API_KEY ?? "",
            sepolia: envs.ETHERSCAN_API_KEY ?? "",
            holesky: envs.ETHERSCAN_API_KEY ?? ""
            // hoodi: envs.ETHERSCAN_API_KEY ?? ""
        }
    },
    sourcify: {
        enabled: enableSourcify
    },
    gasReporter: {
        enabled: envs.REPORT_GAS !== undefined,
        excludeContracts: ["vendor/"],
        // currency: "USD", // "CHF", "EUR", etc.
        darkMode: true,
        showMethodSig: true,
        L1Etherscan: envs.ETHERSCAN_API_KEY
        // trackGasDeltas: true // Track and report changes in gas usage between test runs.
    },
    mocha: {
        timeout: 100000,
        parallel: !mochaSerial,
        bail: mochaBail
    },
    docgen: {
        pages: "files",
        exclude: ["mocks/", "vendor/", "contracts-exposed/", "test/"]
    },
    contractSizer: {
        except: ["mocks/", "vendor/", "contracts-exposed/", "test/"]
    },
    abiExporter: [
        {
            path: "./abi/json",
            format: "json",
            except: abiExporterExceptions,
            spacing: 4
        },
        {
            path: "./abi/minimal",
            format: "minimal",
            except: abiExporterExceptions,
            spacing: 4
        },
        {
            path: "./abi/full",
            format: "fullName",
            except: abiExporterExceptions,
            spacing: 4
        }
    ]
    // exposed: {
    //     imports: true,
    //     initializers: true,
    //     exclude: ["vendor/**/*"]
    // }
};

if (envs.EVM_VERSION !== "default")
    // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
    (config.solidity! as MultiSolcUserConfig).compilers[0].settings!.evmVersion = envs.EVM_VERSION ?? "prague";

// By default fork from the latest block.
if (envs.FORKING_BLOCK_NUMBER) config.networks!.hardhat!.forking!.blockNumber = +envs.FORKING_BLOCK_NUMBER;
if (envs.HARDFORK !== "default") config.networks!.hardhat!.hardfork = envs.HARDFORK ?? "prague";

// Extra settings for `hardhat-gas-reporter`.
if (envs.COINMARKETCAP_API_KEY) config.gasReporter!.coinmarketcap = envs.COINMARKETCAP_API_KEY;
if (envs.REPORT_GAS_FILE_TYPE === "md") {
    config.gasReporter!.outputFile = "gas-report.md";
    config.gasReporter!.reportFormat = "markdown";
    config.gasReporter!.forceTerminalOutput = true;
    config.gasReporter!.forceTerminalOutputFormat = "terminal";
}
if (envs.REPORT_GAS_FILE_TYPE === "json") {
    config.gasReporter!.outputJSON = true;
    config.gasReporter!.outputJSONFile = "gas-report.json";
    config.gasReporter!.includeBytecodeInJSON = true;
}

export default config;
