# CircuitBreaker

![splash](/img/splash.jpg)

CircuitBreaker is an emergency pause manager: a single contract that lets designated pausers pause critical contracts on behalf of the admin.

It's the successor to [GateSeals](https://github.com/lidofinance/gate-seals). Unlike GateSeals, it never needs to be redeployed or have permissions re-granted. The name comes from the analogy: a fuse is one-time use, a circuit breaker resets.

## Design

There are two roles: the **admin** and **pausers** (multisig committees). The admin assigns a pauser to each pausable contract. One pauser can cover multiple contracts, but each contract has exactly one pauser.

In an emergency, the pauser triggers a pause on a contract address. The caller must be the assigned pauser for that contract and must have an active heartbeat. The contract is paused for the globally configured pause duration, which is updatable by the admin. Batch calls can be constructed externally (e.g. via multisig multi-send).

After a successful pause, the pauser assignment is cleared. The admin has to explicitly re-assign before the contract can be paused again.

Pause duration is a single global value (within min/max bounds set at deployment) that applies to all pausables.

Pausers must periodically send a heartbeat for any pausable they're registered for to prove liveness (also done automatically on pause). A pauser whose heartbeat has expired cannot pause or refresh their heartbeat. The admin configures the heartbeat interval within bounds set at deployment.

## vs. GateSeal

GateSeal V1 expired after ~1 year and had to be redeployed. The proposed GateSeal V2 extended the lifetime but added significant configuration complexity and still required re-granting permissions after each use. 

For Foundry docs: https://book.getfoundry.sh/