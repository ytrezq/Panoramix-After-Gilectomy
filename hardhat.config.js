require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-web3");
require("@nomiclabs/hardhat-ethers");
require('hardhat-contract-sizer');
require("@nomicfoundation/hardhat-verify");

const secret = require('./dev-keys.json');

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      accounts: {
        mnemonic: secret.mnemonic,
      },
      forking: {
        url: `https://arb-mainnet.g.alchemy.com/v2/${secret.alchemyKey}`,
        blockNumber: 385250800, // <-- edit here
      },
    },
    mainnet: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${secret.alchemyKey}`,
      accounts: {
        mnemonic: secret.mnemonic,
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.26",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },
  mocha: {
    timeout: 2000000
  },
  etherscan: {
    apiKey: secret.etherscanAPI,
  },
  sourcify: {
    enabled: true
  },
  contractSizer: {
    alphaSort: false,
    disambiguatePaths: false,
    runOnCompile: false,
    strict: false,
  },
};
