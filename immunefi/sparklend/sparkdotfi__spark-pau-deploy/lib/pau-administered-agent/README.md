# PAU Administered Agent

![Foundry CI](https://github.com/marsfoundation/pau-administered-agent/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/marsfoundation/pau-administered-agent/blob/master/LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

`AdministeredAgent` is a lightweight contract designed for controlled operational delegation.
Actors are allowed to execute arbitrary calls and value transfers from the agent, while role management is split
between separate authorities for grant and revoke actions.

The contract defines four role sets:

- `admins`: full governance over role configuration (`add/remove admin`, `add/remove grantor`, `add/remove revoker`)
- `grantors`: may add actors
- `revokers`: may remove actors
- `actors`: may execute `call`, `batchCall`, and `sendValue`

Unlike standard OpenZeppelin `AccessControl` role admins, this model intentionally separates the right to add an
actor from the right to remove an actor. This allows different operational controls for onboarding vs emergency
offboarding (for example, revokers as live watchdogs that can rapidly remove a misbehaving actor).

`AdministeredAgentFactory` is a minimal deployer that instantiates new `AdministeredAgent` instances with an initial
admin and emits `AdministeredAgentDeployed` for discovery/integration.

## Quick Start

### Testing

```bash
forge test
```

---

<p align="center">
  <img src="https://github.com/user-attachments/assets/84ca8724-b6ad-42ef-9c5b-32abd1bb5e03" height="100"/>
</p>
