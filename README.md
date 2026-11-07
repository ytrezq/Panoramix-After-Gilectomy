# MOC V2 Smart Contract main Protocol

This repository defines the smart contracts solution that builds up the Money on Chain V2 decentralized Protocol. For more information, please refer to the [documentation section](./docs/README.md).

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes. See deployment for notes on how to deploy the project on a live system.

### Prerequisites

What things you need to install the software and how to install them

```bash
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash
# Install proper node version
nvm use
```

Create `.env` file (you can base on [`.env.example`](./.env.example))

### Installing

A step by step series of examples that tell you how to get a development env running

Say what the step will be

```bash
# Install the dependencies
npm install
```

### Generate Types

In order to get contract types you can generate those typings when compiling

```bash
npm run compile
```

## Running the tests

```bash
npm run test
```

### Testing with Waffle

Tests using Waffle are written with Mocha alongside with Chai.

Is recommended to use Gherkin as a language to describe the test cases

```js
describe("Feature: Greeter", () => {
  describe("Scenario: Should return the new greeting once it's changed", () => {
    let greeter: Greeter;
    before("GIVEN a deployed Greeter contract", async () => {
      const factory = await ethers.getContractFactory("Greeter");
      greeter = <Greeter>await factory.deploy("Hello, world!");
      expect(await greeter.greet()).to.equal("Hello, world!");
    });
    it("WHEN greeting message changed", async () => {
      await greeter.setGreeting("Hola, mundo!");
    });
    it("THEN greet returns new greeting message", async () => {
      expect(await greeter.greet()).to.equal("Hola, mundo!");
    });
  });
});
```

We are requiring Chai which is an assertions library. These asserting functions are called "matchers", and the ones we're using here actually come from Waffle.

For more information we suggest reading waffle testing documentation [here](https://hardhat.org/guides/waffle-testing.html#testing).

### Ethereum Security Toolbox

To check the code statically you can use the Ethereum Security Toolbox made by Trail of Bits.

#### Slither

##### Docker Default option

First, get the last docker image

`docker pull trailofbits/eth-security-toolbox`

Then, you could just run the default checking executing

`npm run security-default`

##### Docker Flexible option

Or if you want more flexibility, first execute the command

`npm run security`

and once inside the docker container run

```sh
solc-select 0.8.24
cd project
```

so that you can use the tools there installed.

##### Slither local option

First, install slither:

`pip3 install slither-analyzer`

then run:

`npm run slither`

slither will execute the static analysis using the configuration at `slither.config.json`

for more information [here](https://github.com/crytic/slither)

#### Mythril

Mythril is a security analysis tool for EVM bytecode. It detects security vulnerabilities in smart contracts built for any EVM-compatible blockchains. It uses symbolic execution, SMT solving and taint analysis to detect a variety of security vulnerabilities

First, install from Pypi (Python 3.6-3.9)

`pip3 install mythril`

compile contracts

`npm run compile`

then, for example, execute this command to analyze MocCACoinbase contract

`npm run mythril -- ./contracts/collateral/coinbase/MocCACoinbase.sol`

for more information [here](https://github.com/ConsenSys/mythril)

## Deployment

This solution has a fully functional deploy mechanism following [hardhat deploy](https://github.com/wighawag/hardhat-deploy) standard. But implementation agnostic as it is, it also allows external repositories to define custom network configurations and execute deploys using them.
In that case, you can use the command:  

`npm run export`

After that, artifacts and deployments scripts are copied into the export folder. Then, in another repository, you can install them as a npm github dependency, configure them as external deploy in hardhat config setting all the corresponding deployment parameters.
Setting the a network tag as `testnet` using [tags](https://github.com/wighawag/hardhat-deploy#tags), will allow you to:

1. Deploy and initialize the protocol using a governor mocked to bypass governance restrictions
2. Initialize the protocol with a list of predefined Pegged Tokens by configuration
3. Transfer governance to the real governor once initializations have finished

## Built With

* [Hardhat](https://hardhat.org/) - Task runner

## Contributing

Please read [CONTRIBUTING.md](./CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests.

## Versioning

We use [SemVer](http://semver.org/) and [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/) for versioning. For the versions available, see the [tags on this repository](https://github.com/your/project/tags).

To create a new release execute the script

`npm run release`

## License

See the [LICENSE](./LICENSE) file for details
