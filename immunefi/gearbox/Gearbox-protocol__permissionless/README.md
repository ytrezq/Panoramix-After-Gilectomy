# Gearbox Permissionless

A system for deploying and operating onchain credit markets.

Gearbox Permissionless defines how markets are created, configured, and governed — without requiring custody over funds.

It combines contract verification, deterministic deployments, and curator-driven governance into a single operational layer.

---

## Overview

Gearbox core contracts execute credit.

Permissionless defines how markets are:

- deployed
- configured
- upgraded
- governed

This enables independent curators to operate markets within strict protocol guardrails.

---

## Architecture

### 1. Verification Layer (BCR)

- Onchain registry of contract bytecode  
- Auditor attestations  
- Deterministic deployments (CREATE2)  
- Immutable contract references  

This ensures that every deployed component is verified and reproducible.

---

### 2. Market Engine

- Instance Manager  
- Market Configurator  
- Modular architecture (IRM, oracles, adapters)  

Markets are assembled from verified components and deployed with predefined configurations.

---

### 3. Governance Layer

- Curator roles and permissions  
- Timelock-based upgrades  
- Risk parameter management  

Curators can operate markets, but only within protocol-enforced constraints.

---

## Key Properties

- **Permissionless** — anyone can deploy and manage a market  
- **Non-custodial** — curators never control user funds  
- **Deterministic** — all deployments are verifiable and reproducible  
- **Constrained** — governance operates within strict guardrails  

---

## Why it matters

Most DeFi systems rely on trusted operators.

Gearbox Permissionless replaces trust with constraints:

- execution is fixed at the protocol level  
- upgrades are delayed and transparent  
- deployments are verifiable  

This allows markets to be operated independently without compromising user safety.

---

## Relation to Gearbox

- `core-v3` → executes credit and positions  
- `permissionless` → defines how markets are created and managed  
- `integrations-v3` → connects external protocols  
- `oracles-v3` → provides pricing and risk data  

Together, these components form the Gearbox Protocol.

---

## Status

Actively used in Gearbox V3 markets.

## Important information for contributors
As a contributor to the Gearbox Protocol GitHub repository, your pull requests indicate acceptance of our Gearbox Contribution Agreement. This agreement outlines that you assign the Intellectual Property Rights of your contributions to the Gearbox Foundation. This helps safeguard the Gearbox protocol and ensure the accumulation of its intellectual property. Contributions become part of the repository and may be used for various purposes, including commercial. As recognition for your expertise and work, you receive the opportunity to participate in the protocol's development and the potential to see your work integrated within it. The full Gearbox Contribution Agreement is accessible within the repository for comprehensive understanding. [Let's innovate together!]
