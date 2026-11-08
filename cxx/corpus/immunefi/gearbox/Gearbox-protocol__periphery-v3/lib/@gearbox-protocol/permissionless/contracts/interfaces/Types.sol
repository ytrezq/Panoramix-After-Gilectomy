// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

struct AddressProviderEntry {
    bytes32 key;
    uint256 ver;
    address value;
}

struct AuditReport {
    address auditor;
    string reportUrl;
    bytes signature;
}

struct Bytecode {
    bytes32 contractType;
    uint256 version;
    bytes initCode;
    address author;
    string source;
    bytes authorSignature;
}

struct BytecodePointer {
    bytes32 contractType;
    uint256 version;
    address[] initCodePointers;
    address author;
    string source;
    bytes authorSignature;
}

struct Call {
    address target;
    bytes callData;
}

struct ConnectedPriceFeed {
    address token;
    address[] priceFeeds;
}

struct CrossChainCall {
    uint256 chainId; // 0 means to be executed on all chains
    address target;
    bytes callData;
}

struct DeployParams {
    bytes32 postfix;
    bytes32 salt;
    bytes constructorParams;
}

struct DeployResult {
    address newContract;
    Call[] onInstallOps;
}

struct MarketFactories {
    address poolFactory;
    address priceOracleFactory;
    address interestRateModelFactory;
    address rateKeeperFactory;
    address lossPolicyFactory;
}

struct PriceFeedInfo {
    string name;
    uint32 stalenessPeriod;
    bytes32 priceFeedType;
    uint256 version;
}

struct SignedBatch {
    string name;
    bytes32 prevHash;
    CrossChainCall[] calls;
    bytes[] signatures;
}

struct SignedRecoveryModeMessage {
    uint256 chainId;
    bytes32 startingBatchHash;
    bytes[] signatures;
}

struct Split {
    bool initialized;
    address[] receivers;
    uint16[] proportions;
}

struct TwoAdminProposal {
    bytes callData;
    bool confirmedByAdmin;
    bool confirmedByTreasuryProxy;
}
