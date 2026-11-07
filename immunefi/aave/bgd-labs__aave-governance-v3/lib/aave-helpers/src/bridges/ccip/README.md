# AaveGhoCcipBridge

The AaveGhoCcipBridge is a contract to facilitate moving GHO from Ethereum Mainnet to other networks utilizing the underlying CCIP infrastructure from Chainlink. The GHO obtained on the receiving network is immediately transferred automatically to the COLLECTOR instance of that network. The contract also allows sending GHO across networks, as well as back to Ethereum Mainnet.

# Funding

The contract must be funded with fee tokens in order for the message to be executed. Most networks will support GHO as a fee token, but in case it is not supported at the beginning, LINK can be used.
During a governance proposal, GHO/LINK can be sent to the CCIP instance that will be bridging the GHO tokens to another network.
The easiest flow is to have the contract funded with tokens beforehand as it's very cheap to bridge.

From mainnet to another network the cost of a message is ~1.50. From a non-mainnet network to Mainnet the cost is ~0.50.
Billing costs can be found [here](https://docs.chain.link/ccip/billing)

# Permissions

The contract implements Ownable for permissioned functions.
The Owner will always be the respective network's Level 1 Executor (Governance).

# Security Considerations

A new destination chain and corresponding bridge contract must be previously pre-approved by governance.
The contract inherits from `Rescuable`. Using the inherited functions it can transfer tokens out from this contract.
In the case of malformed or invalid messages, the contract implements a rescue mechanism to send tokens to the Collector contract,
following CCIP's defensive approach as shown here:
https://github.com/smartcontractkit/chainlink/blob/62c23768cd483b179301625603a785dd773f2c78/contracts/src/v0.8/ccip/applications/DefensiveExample.sol

# Destination Chains

The chain selector for a given chain is defined by CCIP. The list of chain selectors can be found here:
https://docs.chain.link/ccip/directory/mainnet

Non-EVM chains are supported.

### Destination Addresses

The destination chain address must be provided as bytes. For EVM chains, convert the address to bytes with `abi.encode(address)`, where address is an EVM address (ie: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2). For Solana/Aptos, `abi.encode(bytes32)` where bytes32 is the Aptos/Solana address (ie: A7FMMgue4aZmPLLoutVtbC7gJcyqkHybUieiaDg9aaVE).

### Gas Limits

CCIP docs on gas limits can be found [here](https://docs.chain.link/ccip/tutorials/evm/ccipreceive-gaslimit)

In order to profile gas limits, a user can run tests with the `--gas-report` flag enabled to get an estimate of the gas costs incurred. Adding a few percentage points for safety is always recommended. From tests, for EVM to EVM messages, the average cost is around 65,000 gas used by the `ccipReceive()` function so a gas limit of 100,000 should be more than enough and is 50% of the default gas-limit of 200,000 established by CCIP which would save the DAO a lot of gas. Gas not used is lost.

Even if a function cannot be executed because of insufficient gas automatically, a transaction can always be manually executed at a later time with a higher gas cost.
