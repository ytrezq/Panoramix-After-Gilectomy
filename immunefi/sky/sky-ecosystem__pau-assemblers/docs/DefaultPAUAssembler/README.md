# Default PAU Assembler

`DefaultPAUAssembler` deploys and fully wires a Prime PAU stack plus any number of `AdministeredAgent` allocators in a single transaction, transfers administrative rights to caller-supplied admins, and renounces every role it held during setup. After the call returns the assembler holds **no** privileged role on any deployed contract.

Implementation version: `1.0.0` (`VERSION`).

## Dependencies

The assembler is constructed with two underlying factories and calls into them at deploy time:

| Constructor argument        | Type                            | Role                                                      |
| --------------------------- | ------------------------------- | --------------------------------------------------------- |
| `pauFactory_`               | `IPAUFactoryLike`               | Deploys AccessControls, ALMProxy, RateLimits, Controller. |
| `administeredAgentFactory_` | `IAdministeredAgentFactoryLike` | Deploys each `AdministeredAgent` allocator.               |

Both must be non-zero (`ZeroPAUFactory` / `ZeroAdministeredAgentFactory`). The PAU factory points its deployed Controllers at a shared **Beacon**; integrations must be registered on that Beacon _before_ they can be passed to `deploy` (see [Preconditions](#preconditions--behavior)).

> **Auditor note — dependency status.** The assembler has **no compile-time dependency** on the underlying contracts: `src/` interacts with them solely through the inline `*Like` adapter interfaces, so the production bytecode imports neither repository. Integration tests fork the target chain and call canonical on-chain `PAUFactory` and `AdministeredAgentFactory` deployments, which avoids pulling those repositories in as submodules.

## Entry point

```solidity
function deploy(
    bytes32[]                 memory integrationIds,
    AdminConfig               memory adminConfig,
    AdministeredAgentConfig[] memory allocatorAgentConfigs
)
    external
    returns (
        address          proxy,
        address          controller,
        address          accessControls,
        address          rateLimits,
        address[] memory allocatorAgents
    );
```

There is a single deploy path. It always wires a standard `ALMProxy` (via `deployALMProxy` on the underlying PAU factory) and grants the Controller `CONTROLLER` on the proxy — the role that gates `doCall`.

## Runtime model

The assembler separates **who may administer the stack** from **who may drive allocator actions**:

| Layer           | Who                                            | Role on AccessControls               | How they act                                                                           |
| --------------- | ---------------------------------------------- | ------------------------------------ | -------------------------------------------------------------------------------------- |
| Stack admin     | addresses in `adminConfig`                     | `DEFAULT_ADMIN_ROLE` (per component) | govern AccessControls, ALMProxy, RateLimits, and (indirectly) the Controller           |
| Allocator agent | each deployed `AdministeredAgent` contract     | `ALLOCATOR_ROLE`                     | holds the on-chain allocator identity for the PAU                                      |
| Actor           | addresses in `allocatorAgentConfigs[i].actors` | none on the PAU stack                | call into the Controller (or other targets) via `AdministeredAgent.call` / `batchCall` |

`ALLOCATOR_ROLE` is granted to the **agent contract address**, not to the actor EOAs. Actors operate the stack by routing calls through their agent; only addresses listed as `actors` on that agent may do so (`NotActor` otherwise).

A typical operational path (exercised end-to-end in `TransferAssetFacet.t.sol`):

```text
actor EOA
  → AdministeredAgent.call(controller, …)
    → Controller (facet entrypoint)
      → ALMProxy.doCall
        → external protocol / token
```

Rate limits, proxy funding, and other runtime policy are **not** configured by the assembler — admins set those after deploy (see [Post-deploy operations](#post-deploy-operations)).

## Deploy flow

1. **Deploy the PAU stack** — AccessControls, ALMProxy, RateLimits, and Controller (all administered by the assembler initially).
2. **Deploy and configure allocators** — for each `allocatorAgentConfigs` entry, deploy an `AdministeredAgent` (with the assembler as its constructor admin), then in order: add `admins`, `actors`, `grantors`, and `revokers`; finally remove the assembler as an agent admin.
3. **Wire roles** — grant `DEFAULT_ADMIN_ROLE` on ALMProxy, RateLimits, and AccessControls from `adminConfig`; grant the Controller `CONTROLLER` on the proxy and RateLimits; grant each deployed agent `ALLOCATOR_ROLE` on AccessControls.
4. **Register integrations** — `Controller.updateIntegrations(integrationIds)`, **skipped** when the list is empty.
5. **Renounce** — the assembler revokes its own `DEFAULT_ADMIN_ROLE` on AccessControls, ALMProxy, and RateLimits.

A `Deployment` event is emitted with every deployed address and the full configuration.

## Resulting permission layout

After a successful deploy:

| Contract          | Role                  | Holders                                                |
| ----------------- | --------------------- | ------------------------------------------------------ |
| AccessControls    | `DEFAULT_ADMIN_ROLE`  | `adminConfig.accessControlAdmins`                      |
| AccessControls    | `ALLOCATOR_ROLE`      | each deployed `AdministeredAgent` in `allocatorAgents` |
| ALMProxy          | `DEFAULT_ADMIN_ROLE`  | `adminConfig.proxyAdmins`                              |
| ALMProxy          | `CONTROLLER`          | the Controller                                         |
| RateLimits        | `DEFAULT_ADMIN_ROLE`  | `adminConfig.rateLimitsAdmins`                         |
| RateLimits        | `CONTROLLER`          | the Controller                                         |
| AdministeredAgent | admin                 | per-agent `allocatorAgentConfigs[i].admins`            |
| AdministeredAgent | actor/grantor/revoker | per-agent `actors` / `grantors` / `revokers`           |
| **the assembler** | —                     | **nothing** (all bootstrap roles renounced)            |

> **Note.** The Controller has no roles of its own — admin actions on it are authorized against `DEFAULT_ADMIN_ROLE` on AccessControls. Holders of `accessControlAdmins` therefore also effectively govern the Controller.

Post-deploy invariants checked by `DefaultPAUAssembler.t.sol`:

- The assembler holds `DEFAULT_ADMIN_ROLE` on AccessControls, ALMProxy, and RateLimits — **false**.
- The assembler is an admin on any deployed agent — **false** (removed during step 2).
- `ALLOCATOR_ROLE` on AccessControls is administered by `DEFAULT_ADMIN_ROLE` (OpenZeppelin default).
- The Controller's `beacon`, `proxy`, `rateLimits`, and `accessControls` reference the contracts deployed in the same call; its `beacon` matches the underlying `PAUFactory`'s beacon.

## Configuration reference

### `AdminConfig`

Admins for each PAU component. **Each array must contain at least one address** (`NoDefaultAdmins`); every entry must be non-zero (`ZeroDefaultAdmin`).

| Field                 | Granted on     |
| --------------------- | -------------- |
| `accessControlAdmins` | AccessControls |
| `proxyAdmins`         | ALMProxy       |
| `rateLimitsAdmins`    | RateLimits     |

The same address — and even the same memory array — may be reused across all three fields when one account should administer every PAU component (both integration tests do this).

### `AdministeredAgentConfig[]`

One entry per allocator agent. The array length determines how many `AdministeredAgent` contracts are deployed; each receives `ALLOCATOR_ROLE` on AccessControls.

| Field      | Meaning                                                       |
| ---------- | ------------------------------------------------------------- |
| `admins`   | Agent admins (must be non-empty per entry — `NoAgentAdmins`). |
| `actors`   | May execute `call` / `batchCall` / `sendValue` on the agent.  |
| `grantors` | May add actors on the agent (may be empty).                   |
| `revokers` | May remove actors on the agent (may be empty).                |

`grantors` and `revokers` are independent: a valid deploy may set multiple `actors`, zero `grantors`, and multiple `revokers` on the same agent. These are **agent-level** revokers (who may call `removeActor`), not ALMProxy freezer roles.

The same address may appear in `admins` and in `actors` (or across `AdminConfig` and agent config) when one account both administers the stack and acts through the agent.

### Integrations

`integrationIds` is passed to `Controller.updateIntegrations`. When non-empty, each id must already be registered on the Beacon the underlying `PAUFactory` uses. When empty, the call is skipped and `Controller.integrations()` returns an empty list after deploy.

## Preconditions & behavior

- **Each admin array must be non-empty.** `AdminConfig.accessControlAdmins`, `proxyAdmins`, and `rateLimitsAdmins`, and each `AdministeredAgentConfig.admins`, must contain at least one address (`NoDefaultAdmins` / `NoAgentAdmins`).
- **No zero admins.** Any admin address in `AdminConfig` must be non-zero (`ZeroDefaultAdmin`).
- **Integrations must be pre-registered on the Beacon.** `updateIntegrations` reads each id's config (facet + selector wiring) from the Beacon the underlying `PAUFactory` points at. Unknown ids revert.
- **Empty `integrationIds` is supported** — the `updateIntegrations` call is skipped (the Controller reverts on an empty array), so a stack can be deployed bare and configured later by an admin.
- **Empty `grantors` / `revokers` / `actors` arrays are supported** on an agent (subject to each agent still having at least one admin).
- **Duplicate / overlapping entries behave differently per component.**
    - On the **AdministeredAgent**, re-adding an account reverts the whole deploy — duplicate `admins`, `actors`, `grantors`, or `revokers` within a single config revert with `AccountAlreadyAdmin` / `AccountAlreadyActor` / `AccountAlreadyGrantor` / `AccountAlreadyRevoker` from the agent contract.
    - On **AccessControls / ALMProxy / RateLimits**, roles are granted through OpenZeppelin `grantRole`, which is **idempotent**: re-granting an already-held role is a silent no-op. Duplicates within `accessControlAdmins` / `proxyAdmins` / `rateLimitsAdmins` are therefore harmless (no revert), not guarded.

## Security & trust

- **Trustless post-deploy.** The assembler revokes `DEFAULT_ADMIN_ROLE` on AccessControls, ALMProxy, and RateLimits and removes itself as an admin on every deployed agent; it retains no control over any deployed contract.
- **One-shot and non-upgradeable.** Each call deploys a fresh, independent stack.
- **Deterministic surface.** Roles are wired only as described above; no rate limits, proxy balances, or role-admin overrides are configured beyond the supplied inputs. `ALLOCATOR_ROLE` remains administered by `DEFAULT_ADMIN_ROLE` on AccessControls (OpenZeppelin default).

## Event

```solidity
event Deployment(
    address                   indexed proxy,
    address                   indexed controller,
    address                           accessControls,
    address                           rateLimits,
    address[]                         allocatorAgents,
    bytes32[]                         integrationIds,
    AdminConfig                       adminConfig,
    AdministeredAgentConfig[]         allocatorAgentConfigs
);
```
