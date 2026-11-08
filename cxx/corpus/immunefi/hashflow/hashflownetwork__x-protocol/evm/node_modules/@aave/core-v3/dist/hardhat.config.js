"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// @ts-ignore
const test_wallets_js_1 = require("./test-wallets.js");
const constants_1 = require("./helpers/constants");
const helper_hardhat_config_1 = require("./helper-hardhat-config");
require('dotenv').config();
require("@nomicfoundation/hardhat-toolbox");
require("hardhat-deploy");
require("@tenderly/hardhat-tenderly");
require("hardhat-contract-sizer");
require("hardhat-dependency-compiler");
require("@nomicfoundation/hardhat-chai-matchers");
const deploy_v3_1 = require("@aave/deploy-v3");
const DEFAULT_BLOCK_GAS_LIMIT = 12450000;
const HARDFORK = 'london';
const hardhatConfig = {
    gasReporter: {
        enabled: true,
    },
    contractSizer: {
        alphaSort: true,
        runOnCompile: false,
        disambiguatePaths: false,
    },
    solidity: {
        // Docs for the compiler https://docs.soliditylang.org/en/v0.8.10/using-the-compiler.html
        version: '0.8.10',
        settings: {
            optimizer: {
                enabled: true,
                runs: 100000,
            },
            evmVersion: 'london',
        },
    },
    typechain: {
        outDir: 'types',
        target: 'ethers-v5',
    },
    mocha: {
        timeout: 0,
        bail: true,
    },
    tenderly: {
        project: process.env.TENDERLY_PROJECT || '',
        username: process.env.TENDERLY_USERNAME || '',
        forkNetwork: '1', //Network id of the network we want to fork
    },
    networks: {
        coverage: {
            url: 'http://localhost:8555',
            chainId: constants_1.COVERAGE_CHAINID,
            throwOnTransactionFailures: true,
            throwOnCallFailures: true,
        },
        hardhat: {
            hardfork: HARDFORK,
            blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
            gas: DEFAULT_BLOCK_GAS_LIMIT,
            gasPrice: 8000000000,
            chainId: constants_1.HARDHAT_CHAINID,
            throwOnTransactionFailures: true,
            throwOnCallFailures: true,
            forking: (0, helper_hardhat_config_1.buildForkConfig)(),
            allowUnlimitedContractSize: true,
            accounts: test_wallets_js_1.accounts.map(({ secretKey, balance }) => ({
                privateKey: secretKey,
                balance,
            })),
        },
        ganache: {
            url: 'http://ganache:8545',
            accounts: {
                mnemonic: 'fox sight canyon orphan hotel grow hedgehog build bless august weather swarm',
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
    },
    namedAccounts: {
        ...deploy_v3_1.DEFAULT_NAMED_ACCOUNTS,
    },
    external: {
        contracts: [
            {
                artifacts: './temp-artifacts',
                deploy: 'node_modules/@aave/deploy-v3/dist/deploy',
            },
        ],
    },
};
exports.default = hardhatConfig;
