# ZenStaker

A staking platform for the **ZEN token**, built on top of [Tally's audited Staker contracts](https://github.com/withtally/staker).

Users stake ZEN to earn ZEN rewards. The smart-contract layer is a thin, additive wrapper over the audited base: the only changes are view-only helper functions that reduce RPC round-trips for the frontend. All write-path logic (stake, withdraw, claim) is inherited unchanged.

---

## Project goal

ZenStaker gives Horizen holders a native staking experience:

1. **Stake ZEN** - deposit any amount of ZEN into an on-chain position.
2. **Earn ZEN rewards** - rewards accrue continuously, proportional to each user's share of total staked ZEN.
3. **Claim at any time** - no lock-up periods; rewards can be claimed whenever the user wants.
4. **Delegate** - each deposit designates a delegatee address (governance-forwarding is out of scope for Phase 1; a non-voting surrogate holds the tokens).
5. **Custom claimer** - reward collection can be delegated to a separate address (e.g. a vesting contract).

The frontend reads all the data it needs in as few RPC calls as possible by calling the batch view helpers added to `ZenStaker.sol`.

---

## User-facing features

### Stake

Deposit ZEN into a new position. Each deposit gets a unique ID and designates:
- a **delegatee** - the address that receives the deposit's (non-voting) surrogate delegation;
- an optional **claimer** - a separate address authorised to claim rewards on the owner's behalf.

Two paths:
- `approve` + `stake(amount, delegatee)` - two transactions.
- `permitAndStake(amount, delegatee, claimer, deadline, v, r, s)` - single transaction using an EIP-2612 signature. **Note:** the production ZEN token does not implement EIP-2612 `permit`. The inherited code swallows the failed permit (`try/catch`), so without a pre-existing allowance the call reverts at `transferFrom` — the single-transaction path only works with permit-capable test tokens.

### Stake more

Add ZEN to an existing deposit without opening a new one:  
`stakeMore(depositId, amount)` - owner only; preserves the existing delegatee and claimer.

### Claim rewards

Collect accrued ZEN rewards for a deposit:  
`claimReward(depositId)` - callable by the deposit **owner** or its **claimer**.  
Rewards are sent directly to the caller. There are no fees (fee is fixed at 0 in Phase 1).

### Withdraw

Pull staked ZEN out of a deposit (partially or fully):  
`withdraw(depositId, amount)` - owner only.  
Rewards are **not** claimed automatically; call `claimReward` first to avoid leaving them stranded.

### Change delegatee

Reassign the surrogate delegation of an existing deposit:  
`alterDelegatee(depositId, newDelegatee)` - owner only.

### Change claimer

Reassign the address authorised to collect rewards for a deposit:  
`alterClaimer(depositId, newClaimer)` - owner only.

---

## Architecture

```
ZenStaker (src/ZenStaker.sol)
  ├── inherits Staker (src/Staker.sol)          ← audited by Sherlock, Offbeat, Cantina
  ├── inherits StakerPermitAndStake              ← EIP-2612 single-tx stake
  └── adds view helpers (no new state)
        getDepositInfo(id)
        getDepositsInfo(ids[])
        getGlobalState()
        getDepositorSummary(addr)
        getDepositorFullSummary(addr, ids[])

ZenDelegationSurrogate (src/ZenStaker.sol)
  └── inherits DelegationSurrogate               ← holds staked tokens, no vote delegation

IdentityEarningPowerCalculator (src/calculators/)
  └── earning power == stake (1:1), used in Phase 1
```

### What was changed vs. the audited base

All changes are **additive only**. No write-path logic, storage layout, or function behaviour was altered.

| Change | Kind | Behavioural impact |
|--------|------|--------------------|
| `src/ZenStaker.sol` - new file | New concrete implementation | Inherits audited base; adds view helpers |
| `StakeDeposited.owner` → `indexed` | Event schema | None - enables efficient frontend filtering |
| `StakeWithdrawn.owner` → `indexed` | Event schema | None - enables efficient frontend filtering |

See [AUDIT_DELTA.md](AUDIT_DELTA.md) for the full audit-diff rationale.

---

## Frontend integration

The frontend reads on-chain state through the view helpers and listens to indexed events to discover deposit IDs (deposit IDs are not enumerable on-chain).

Key contract calls:

| What to display | Function |
|-----------------|----------|
| Protocol-wide ZEN staked & reward rate | `getGlobalState()` |
| User's total staked (no deposit IDs needed) | `getDepositorSummary(addr)` |
| User's total staked + unclaimed rewards | `getDepositorFullSummary(addr, ids[])` |
| Per-deposit breakdown | `getDepositsInfo(ids[])` |
| Discover deposit IDs | `StakeDeposited` events filtered by `owner` (indexed) |

For the complete ethers.js integration guide (TypeScript snippets, ABI, error handling, event subscription) see [docs/frontend-integration.md](docs/frontend-integration.md).

---

## Repository layout

```
src/
  ZenStaker.sol                          # ZEN-specific concrete implementation
  Staker.sol                             # Audited base (Tally)
  calculators/
    IdentityEarningPowerCalculator.sol   # Phase 1: earning power == stake
  extensions/
    StakerPermitAndStake.sol             # EIP-2612 single-tx stake
    ...
script/
  DeployZenStaker.s.sol                  # Foundry deployment script
  ConfigureRewardNotifier.s.sol          # Post-deploy admin script
test/e2e/
  e2e-zen-staker.js                      # Node.js end-to-end test (ethers v6)
docs/
  frontend-integration.md               # ethers.js integration guide
audits/                                  # All upstream audit reports
AUDIT_DELTA.md                          # Change summary for auditors
```

---

## Development

### Prerequisites

- [Foundry](https://getfoundry.sh) - for Solidity build and tests
- Node.js ≥ 18 + npm - for the e2e script

### Build

```bash
forge install
forge build
```

### Solidity tests

```bash
forge test
```

### End-to-end script

The e2e scripts deploy the contract stack and exercise the entire staking lifecycle (stake → accrue rewards → claim → withdraw).

#### Non-upgradeable variant (ZenStaker)
**Against a local Anvil node (no .env needed):**
```bash
npm install
npm run e2e:anvil
```

**Against a testnet:**
```bash
cp .env.template .env
# fill in: RPC_URL, DEPLOYER_PRIVATE_KEY, USER1_PRIVATE_KEY, USER2_PRIVATE_KEY
npm run e2e
```

### Deployment (Foundry)

To deploy the **non-upgradeable** `ZenStaker` implementation using Foundry, you will use the provided scripts in the `script/` directory.

#### 1. Deploy ZenStaker & IdentityEarningPowerCalculator
Export the following environment variables (or set them in `.env`):
* `ZEN_TOKEN_ADDRESS`: Address of the deployed ZEN ERC20 token.
* `ADMIN_ADDRESS`: Address of the Horizen multisig (becomes staker admin).
* `PRIVATE_KEY`: Deployer private key (hex, with or without 0x prefix).
* `MAX_BUMP_TIP` (Optional): Maximum bump tip (defaults to 0).

Execute the deploy script:
```bash
forge script script/DeployZenStaker.s.sol --rpc-url $RPC_URL --broadcast
```

#### 2. Configure Reward Notifiers (Post-Deploy)
To authorize a contract or account to send rewards to the staker, export these variables:
* `STAKER_ADDRESS`: Address of the deployed `ZenStaker` contract.
* `REWARD_NOTIFIER_ADDRESS`: Address of the reward notifier to enable.
* `PRIVATE_KEY`: Admin private key (must be the `ADMIN_ADDRESS` specified during deploy).

Execute the configuration script:
```bash
forge script script/ConfigureRewardNotifier.s.sol --rpc-url $RPC_URL --broadcast
```

---

## Audits

ZenStaker inherits the Tally Staker base at tag `v1.0.1`, which was audited by:

- [Sherlock](audits/2024_12_Staker_Sherlock_Audit_Report.pdf) (Nov 2024 contest + Jan 2025 public contest)
- [Offbeat Security](audits/2025_01_Reward_Notifiers_Offbeat_Security_Audit_Report.pdf) (Jan 2025)
- Cantina (public contest)
- ToB + Code4rena on the original UniStaker foundation (see [audits/unistaker/](audits/unistaker/))

The ZenStaker additions (view helpers + event indexing) are stateless and require no re-audit of core logic; see [AUDIT_DELTA.md](AUDIT_DELTA.md).

---

## License

AGPL-3.0-only - see [LICENSE](LICENSE).
