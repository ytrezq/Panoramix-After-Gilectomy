require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-web3");
require("@nomiclabs/hardhat-ethers");
require('hardhat-contract-sizer');
require("@nomicfoundation/hardhat-verify");

const keys = require('./dev-keys.json');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts: {
        mnemonic: keys.mnemonic,
      },
      allowUnlimitedContractSize: true,
      forking: {
        url: "https://eth-mainnet.g.alchemy.com/v2/" + keys.alchemyKeyMainnet,
        blockNumber: 23489150, // <-- edit here
      },
    },
    mainnet: {
      url: "https://eth-mainnet.g.alchemy.com/v2/" + keys.alchemyKeyMainnet,
      accounts: {
        mnemonic: keys.mnemonic,
      },
    },
  },
  solidity: {
    compilers: [{
        version: "0.8.26",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          },
        },
      },
    ],
  },
  mocha: {
    timeout: 2000000,
  },
  etherscan: {
    apiKey: keys.etherscanAPI,
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
