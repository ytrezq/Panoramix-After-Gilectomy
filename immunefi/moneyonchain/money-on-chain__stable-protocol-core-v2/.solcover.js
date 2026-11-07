// The environment variables are loaded in hardhat.config.ts
const mnemonic = process.env.MNEMONIC;
if (!mnemonic) {
  throw new Error("Please set your MNEMONIC in a .env file");
}

module.exports = {
  istanbulReporter: ["html", "lcov", "cobertura"],
  providerOptions: {
    mnemonic,
  },
  skipFiles: ["mocks", "test"],
  mocha: {
    grep: /.*gas estimation.*/i,
    invert: true,
  },
};
