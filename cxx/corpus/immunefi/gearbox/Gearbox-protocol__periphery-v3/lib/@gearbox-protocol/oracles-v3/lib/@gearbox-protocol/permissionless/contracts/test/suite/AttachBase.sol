// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {CommonBase} from "forge-std/Base.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {IInstanceManager} from "../../interfaces/IInstanceManager.sol";
import {IMarketConfiguratorFactory} from "../../interfaces/IMarketConfiguratorFactory.sol";
import {IPriceFeedStore} from "../../interfaces/IPriceFeedStore.sol";
import {AuditReport, Bytecode} from "../../interfaces/Types.sol";

import {
    AP_BYTECODE_REPOSITORY,
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_INSTANCE_MANAGER,
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_PRICE_FEED_STORE,
    AP_TREASURY,
    NO_VERSION_CONTROL
} from "../../libraries/ContractLiterals.sol";

abstract contract AttachBase is CommonBase {
    address public constant ADDRESS_PROVIDER = 0xF7f0a609BfAb9a0A98786951ef10e5FE26cC1E38;

    IAddressProvider public addressProvider;
    IBytecodeRepository public bytecodeRepository;
    IInstanceManager public instanceManager;
    IPriceFeedStore public priceFeedStore;
    IMarketConfiguratorFactory public marketConfiguratorFactory;

    address public crossChainGovernance;
    address public instanceOwner;
    address public treasury;

    function _attachCore() internal virtual {
        if (ADDRESS_PROVIDER.code.length == 0) revert("Instance is not deployed");
        addressProvider = IAddressProvider(ADDRESS_PROVIDER);
        bytecodeRepository =
            IBytecodeRepository(addressProvider.getAddressOrRevert(AP_BYTECODE_REPOSITORY, NO_VERSION_CONTROL));
        instanceManager = IInstanceManager(addressProvider.getAddressOrRevert(AP_INSTANCE_MANAGER, NO_VERSION_CONTROL));
        priceFeedStore = IPriceFeedStore(addressProvider.getAddressOrRevert(AP_PRICE_FEED_STORE, NO_VERSION_CONTROL));
        marketConfiguratorFactory = IMarketConfiguratorFactory(
            addressProvider.getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL)
        );
        crossChainGovernance = addressProvider.getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL);
        instanceOwner = instanceManager.owner();
        treasury = addressProvider.getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL);
    }

    /// @dev For test environments
    function _signBytecode(VmSafe.Wallet memory author, Bytecode memory bytecode) internal view {
        bytecode.author = author.addr;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(author.privateKey, _getBytecodeDigest(bytecode));
        bytecode.authorSignature = abi.encodePacked(r, s, v);
    }

    /// @dev For script environments
    function _signBytecode(address author, Bytecode memory bytecode) internal view {
        bytecode.author = author;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(author, _getBytecodeDigest(bytecode));
        bytecode.authorSignature = abi.encodePacked(r, s, v);
    }

    function _getBytecodeDigest(Bytecode memory bytecode) internal view returns (bytes32) {
        bytes32 domainSeparator = bytecodeRepository.domainSeparatorV4();
        bytes32 bytecodeHash = bytecodeRepository.computeBytecodeHash(bytecode);
        return ECDSA.toTypedDataHash(domainSeparator, bytecodeHash);
    }

    /// @dev For test environments
    function _signAuditReport(VmSafe.Wallet memory auditor, bytes32 bytecodeHash, AuditReport memory auditReport)
        internal
        view
    {
        auditReport.auditor = auditor.addr;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(auditor.privateKey, _getAuditReportDigest(bytecodeHash, auditReport));
        auditReport.signature = abi.encodePacked(r, s, v);
    }

    /// @dev For script environments
    function _signBytecode(address auditor, bytes32 bytecodeHash, AuditReport memory auditReport) internal view {
        auditReport.auditor = auditor;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(auditor, _getAuditReportDigest(bytecodeHash, auditReport));
        auditReport.signature = abi.encodePacked(r, s, v);
    }

    function _getAuditReportDigest(bytes32 bytecodeHash, AuditReport memory auditReport)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = bytecodeRepository.domainSeparatorV4();
        bytes32 auditReportHash = bytecodeRepository.computeAuditReportHash(bytecodeHash, auditReport);
        return ECDSA.toTypedDataHash(domainSeparator, auditReportHash);
    }
}
