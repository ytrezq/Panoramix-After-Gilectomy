# Katana Governance Specification

This repository contains the custom contracts used in the Katana governance system, built on top of Aragon's [VE Governance](https://github.com/aragon/ve-governance) system.

## System Overview

The Katana governance system enables users to participate in protocol governance through a vote-escrowed (VE) token mechanism. At its core, users lock their KAT tokens into the Aragon [`VotingEscrow.sol`](https://github.com/aragon/ve-governance/blob/audit-4/src/escrow/VotingEscrowIncreasing_v1_2_0.sol) contract, which mints them "vKAT" - a veNFT position representing their locked tokens.

Unlike some vote-escrow systems where voting power decays over time, vKAT maintains a stable 1:1 voting power ratio with the amount of KAT locked, ensuring predictable governance participation.

When users decide to exit their positions, the system implements a flexible cooldown mechanism via the [`DynamicExitQueue.sol`](https://github.com/aragon/ve-governance/blob/audit-4/src/queue/DynamicExitQueue.sol). Users can choose between immediate exit with a high fee or waiting through a cooldown period where the fee gradually decreases on a per-second basis until reaching a minimum threshold.

### Governance and Emissions

The primary governance activity involves directing KAT emissions to liquidity pools across various protocols including SushiSwap, Spectra, and others.

vKAT holders vote through the [`AddressGaugeVoter.sol`](https://github.com/aragon/ve-governance/blob/audit-4/src/voting/AddressGaugeVoter.sol) system, where their votes determine the allocation of KAT incentives designed to attract liquidity provision.

The actual distribution of these emissions is handled through [Merkl](https://app.merkl.xyz/?action=POOL&chain=747474&test=true), with the KAT allocation to each pool proportional to the gauge votes received relative to the total KAT budget. A multisig transaction initiates the distribution by creating campaigns in Merkl.

### Reward System and Bribes

Beyond directing emissions, vKAT stakers recieve rewards via a bribe system where projects can offer incentives to vKAT stakers to encourage KAT emissions to flow to their pools.

These bribes are also distributed through Merkl and can be claimed in whitelisted reward tokens of the staker's choice, as configured through the [`VKatMetadata`](./src/VKatMetadata.sol) contract. The system includes a permissionless [`Swapper`](./src/Swapper.sol) utility that vKAT stakers can authorize to handle the entire reward flow - from claiming bribes to swapping them into their preferred token, with optional auto-compounding capabilities.

### Voting Flexibility

The system offers multiple approaches to voting participation:

- Users can maintain full control by self-delegating their voting power and voting manually on proposals.
- Alternatively, they can delegate their voting power to professional delegates or automated voting services
  - Aragon will provide a profit-maximizing autovoter at launch, though the delegation system is permissionless and open to any participant.
- For users seeking a fully passive experience, the system offers a solution through the avKAT vault. By exchanging their veNFT for liquid `avKAT` ("autocompounding vKAT") tokens, users gain exposure to an ERC4626 vault that maintains a single consolidated vKAT position. This vault automatically votes using a profit-maximizing strategy and compounds all received rewards back into additional vKAT, creating a token that appreciates in KAT terms over time.
  - Users can later redeem their avKAT tokens for a proportional vKAT NFT to unstake, or simply sell avKAT on the open market to exit their position.

## Contract Architecture

### Core Contracts

- [`VKatMetadata.sol`](./src/VKatMetadata.sol) - Preference management for reward distributions
- [`Swapper.sol`](./src/Swapper.sol) - Permissionless utility for claiming and swapping rewards
- [`AvKATVault.sol`](./src/AvKATVault.sol) - ERC4626 vault for aggregating vKAT positions
- [`Factory.sol`](./src/Factory.sol) - Protocol deployment and configuration
- [`AragonMerklAutoCompoundStrategy.sol`](./src/strategies/AragonMerklAutoCompoundStrategy.sol) - Auto-compounding strategy
- [`DefaultStrategy.sol`](./src/strategies/DefaultStrategy.sol) - Minimal fallback strategy

### VKatMetadata Contract

The VKatMetadata contract enables the protocol to build offchain swap data by maintaining a whitelist of reward tokens and tracking user preferences. This is critical because Merkl distributes rewards in various tokens, and offchain swapper needs to know which tokens users want to receive or whether they prefer auto-compounding when building calldata.

**Workflow and Rationale:**

The contract maintains a curated whitelist of reward tokens controlled by Katana governance. This whitelist serves two purposes: it ensures only vetted tokens can be distributed as rewards, and it allows the offchain infrastructure to pre-build swap routes for these known tokens.

Users specify their reward preferences as percentages across whitelisted tokens. The system uses a reserved address `type(uint160).max` which indicates the user wants to auto-compound rewards back into vKAT.

When rewards are distributed through Merkl, the offchain system reads user preferences from this contract to determine:

1. Which tokens the user wants to receive
2. What percentage of rewards should go to each token
3. Whether any portion should be auto-compounded

This design allows the protocol to handle complex reward distributions while keeping the onchain logic simple and gas-efficient.

### Swapper Contract

The Swapper is a public, permissionless contract that batches multiple operations: claiming rewards from Merkl, executing swaps via SushiSwap, and transferring tokens to users. Users can whitelist the swapper on Merkl by calling `setClaimRecipient` and this allows the swapper to process their claims. Merkl [requires](https://github.com/AngleProtocol/merkl-contracts/blob/main/contracts/Distributor.sol#L378) that the `tx.origin` of the transaction is the original claimant so it is the user that must initiate the claim, but the calldata can be fetched from a service.

**Workflow:**

1. **Offchain Preparation**: Before calling the Swapper, an offchain system:

   - Fetches Merkle proofs from the Merkl API for pending rewards
   - Queries swap routes from router APIs (e.g., SushiSwap) to convert rewards to desired tokens
   - Encodes token transfers and any additional actions into an actions array

2. **Onchain Execution**: The Swapper then:

   - Claims rewards from Merkl using the provided proofs
   - Passes the actions array to the Executor contract, which performs the swaps
   - Transfers the swapped tokens to the user

3. **KAT Compounding** (optional): When the target token is KAT and the user has set auto-compound preferences, the Swapper performs an additional step:
   - Takes the specified portion of KAT
   - Creates or adds to a voting escrow position on behalf of the user

This design keeps the onchain logic minimal while enabling complex multi-step operations. The Executor contract is responsible for the actual swap execution, allowing for upgradeable swap logic without changing the Swapper itself.

### AvKATVault Contract and Strategy System

The AvKATVault is an ERC4626-compliant vault that aggregates individual voting escrow NFT positions into a single "master token" while providing users with fungible avKAT shares. The vault itself handles ERC721 logic (receiving, transferring NFTs) while delegating all escrow-specific operations to external strategy contracts.

**Architecture Design Rationale:**

The vault maintains a clear separation of concerns:

- **Vault responsibilities**: NFT custody, share accounting, deposit/withdrawal logic
- **Strategy responsibilities**: Escrow operations (merging, splitting), voting, claiming rewards, auto-compounding

This separation allows the vault to remain simple and auditable while strategies can be upgraded or replaced to adapt to changing conditions.

**Strategy System:**

1. **DefaultStrategy**: A minimal implementation that provides basic NFT management functionality. This serves as a fallback to ensure the vault can always operate, even if the active strategy is removed. The DefaultStrategy only implements essential functions like merging and splitting NFTs but does not include any reward claiming or voting logic.

2. **AragonMerklAutoCompoundStrategy**: The primary strategy that implements the full auto-compounding logic:
   - Claims rewards from Merkl using the master token
   - Swaps all rewards to KAT through the Swapper contract
   - Donates the KAT back to the vault, increasing the value of all avKAT shares
   - Manages gauge voting and delegation for the master token
   - Inherits from NFTBaseStrategy which provides the core merge/split operations

**Deposit and Withdrawal Flow:**

1. **Deposits**: Users can deposit either KAT tokens (which get locked into a new NFT) or existing vKAT NFTs. The vault:

   - Calculates the deposit value based on the locked amount in the NFT
   - Mints proportional avKAT shares to the depositor
   - Calls the strategy to merge the deposited NFT into the master token

2. **Withdrawals**: Users burn avKAT shares to withdraw. The vault:
   - Calculates the proportional value to withdraw
   - Calls the strategy to split this amount from the master token into a new NFT
   - Transfers the new NFT to the withdrawer
   - Includes slippage protection via `minAmountOut`

**Strategy Switching:**

The vault owner can switch between strategies, but several safeguards are in place:

- The strategy must be whitelisted by the DAO
- The old strategy must return the master token to the vault
- If a strategy is removed without replacement, the vault automatically falls back to the DefaultStrategy
- This ensures the vault can always process withdrawals even if strategies misbehave

### Factory Contract

The Factory contract orchestrates the deployment of the entire protocol stack, handling contract deployment, permission configuration, and initial setup in a single atomic transaction.

**Deployment Process:**

1. Deploys all contracts as UUPS proxies for upgradeability
2. Initializes each contract with proper parameters
3. Prepares DAO actions to:
   - Grant necessary permissions to contracts
   - Whitelist the vault for NFT transfers
   - Enable split functionality for strategies
   - Set up role permissions for administrative functions

The Factory ensures all contracts are properly connected and permissioned before the system goes live, preventing configuration errors.
