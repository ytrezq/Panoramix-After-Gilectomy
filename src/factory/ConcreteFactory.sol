// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

/**
 * @title ConcreteFactory
 * @notice Factory for deploying and managing Concrete vault proxies and implementations.
 *         Supports deterministic deployments (CREATE2) and UUPS upgradeability with ownership controls.
 *
 * @author Blueprint Finance
 * @custom:protocol Concrete Earn V2
 * @custom:oz-upgrades Uses UUPS + eip7201 storage layout
 * @custom:source on request
 * @custom:audits on request
 * @custom:license AGPL-3.0
 */

// ─────────────────────────────────────────────────────────────────────────────
// External dependencies
// ─────────────────────────────────────────────────────────────────────────────
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Create2} from "@openzeppelin-contracts/utils/Create2.sol";
import {EnumerableSet} from "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Protocol-facing interfaces
// ─────────────────────────────────────────────────────────────────────────────
import {IConcreteFactory} from "../interface/IConcreteFactory.sol";
import {IUpgradeableVault} from "../interface/IUpgradeableVault.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Internal contracts
// ─────────────────────────────────────────────────────────────────────────────
import {IVaultProxy, VaultProxy} from "./VaultProxy.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Storage layout libraries
// ─────────────────────────────────────────────────────────────────────────────
import {ConcreteFactoryBaseStorageLib as CFBSLib} from "../lib/storage/ConcreteFactoryBaseStorageLib.sol";

contract ConcreteFactory is IConcreteFactory, UUPSUpgradeable, OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev A modifier to validate version
     * @param version implementation's version
     */
    modifier checkVersion(uint64 version) {
        require(version > 0 && version <= lastVersion(), InvalidVersion());
        _;
    }

    /**
     * @dev Constructor for the ConcreteFactory contract.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the ConcreteFactory contract.
     * @param owner_ The address of the owner of the factory.
     */
    function initialize(address owner_) external initializer {
        __Ownable_init_unchained(owner_);
        __UUPSUpgradeable_init_unchained();
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function approveImplementation(address implementation) external onlyOwner {
        require(IUpgradeableVault(implementation).factory() == address(this), InvalidImplementation());
        // load the storage variable
        CFBSLib.ConcreteFactoryBaseStorage storage $ = CFBSLib.fetch();
        require($.implementations.add(implementation), AlreadyApproved());

        emit ApprovedImplementation(implementation);
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function blockImplementation(uint64 version) external onlyOwner checkVersion(version) {
        CFBSLib.ConcreteFactoryBaseStorage storage $ = CFBSLib.fetch();
        require(!$.blocked[version], AlreadyBlocked());

        $.blocked[version] = true;

        emit Blocked(version);
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function setMigratable(uint64 fromVersion, uint64 toVersion)
        external
        onlyOwner
        checkVersion(fromVersion)
        checkVersion(toVersion)
    {
        require(fromVersion < toVersion, OldVersion());

        CFBSLib.ConcreteFactoryBaseStorage storage $ = CFBSLib.fetch();
        $.migratable[fromVersion][toVersion] = true;

        emit Migratable(fromVersion, toVersion);
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function create(uint64 version, address ownerAddr, bytes calldata data) external returns (address) {
        return create(version, ownerAddr, data, 0);
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function create(uint64 version, address ownerAddr, bytes calldata data, bytes32 salt) public returns (address) {
        address predictedAddress = predictVaultAddress(version, ownerAddr, data, salt);

        CFBSLib.fetch().vaults[predictedAddress] = true;
        bytes memory bytecode = _computeBytecode(version, ownerAddr, data);

        // Deploy using OpenZeppelin Create2
        address concreteVault = Create2.deploy(0, salt, bytecode);

        require(predictedAddress == concreteVault, InvalidVaultAddress());

        // Mark the vault as deployed by this factory

        emit Deployed(concreteVault, version, ownerAddr);

        return concreteVault;
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function predictVaultAddress(uint64 version, address ownerAddr, bytes calldata data)
        external
        view
        returns (address)
    {
        return predictVaultAddress(version, ownerAddr, data, 0);
    }

    function _computeBytecode(uint64 version, address ownerAddr, bytes calldata data)
        internal
        view
        returns (bytes memory)
    {
        require(!isBlocked(version), ImplementationBlocked());

        // Get the implementation address
        address implementation = getImplementationByVersion(version);

        // Encode the constructor parameters
        bytes memory constructorData = abi.encodeCall(IUpgradeableVault.initialize, (version, ownerAddr, data));

        // Create the bytecode for deployment
        return abi.encodePacked(type(VaultProxy).creationCode, abi.encode(implementation, constructorData));
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function predictVaultAddress(uint64 version, address ownerAddr, bytes calldata data, bytes32 salt)
        public
        view
        returns (address)
    {
        bytes memory bytecode = _computeBytecode(version, ownerAddr, data);

        // Compute CREATE2 address using OpenZeppelin
        return Create2.computeAddress(salt, keccak256(bytecode), address(this));
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function upgrade(address vault, uint64 newVersion, bytes calldata data) external {
        _upgrade(vault, newVersion, data);
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function batchUpgrade(address[] calldata vaultAddresses, uint64 newVersion, bytes[] calldata data) external {
        require(vaultAddresses.length == data.length, InvalidDataLength());
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            _upgrade(vaultAddresses[i], newVersion, data[i]);
        }
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function lastVersion() public view returns (uint64) {
        return uint64(CFBSLib.fetch().implementations.length());
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function getImplementationByVersion(uint64 version) public view checkVersion(version) returns (address) {
        return CFBSLib.fetch().implementations.at(version - 1);
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function isBlocked(uint64 version) public view checkVersion(version) returns (bool) {
        return CFBSLib.fetch().blocked[version];
    }

    /**
     * @inheritdoc IConcreteFactory
     */
    function isMigratable(uint64 fromVersion, uint64 toVersion)
        public
        view
        checkVersion(fromVersion)
        checkVersion(toVersion)
        returns (bool)
    {
        return CFBSLib.fetch().migratable[fromVersion][toVersion];
    }

    /**
     * @notice Check if a vault was deployed by this factory
     * @param vault The vault address to check
     * @return True if the vault was deployed by this factory, false otherwise
     */
    function isRegisteredVault(address vault) public view returns (bool) {
        return CFBSLib.fetch().vaults[vault];
    }

    /**
     * @dev Admin function to register an external vault proxy to be managed by this factory
     * useful in case of pre-v2 migrations
     * @param vault The vault address to register
     */
    function registerVault(address vault) external onlyOwner {
        require(vault != address(0), ZeroAddress());
        require(!CFBSLib.fetch().vaults[vault], VaultAlreadyRegistered());
        require(IUpgradeableVault(vault).factory() == address(this), InvalidImplementation());

        CFBSLib.fetch().vaults[vault] = true;

        emit VaultRegistered(vault);
    }

    /**
     * @dev Internal function to upgrade a vault to a new implementation version
     * @param vault The vault address to upgrade
     * @param newVersion The target implementation version
     * @param data Custom data to pass to the new implementation's upgrade function
     */
    function _upgrade(address vault, uint64 newVersion, bytes calldata data) internal {
        require(isRegisteredVault(vault), NotRegisteredVault());
        require(msg.sender == OwnableUpgradeable(vault).owner(), NotOwner());

        uint64 currentVaultVersion = IUpgradeableVault(vault).version();

        require(newVersion > currentVaultVersion, OldVersion());
        require(isMigratable(currentVaultVersion, newVersion), CanNotMigrate());
        require(!isBlocked(newVersion), ImplementationBlocked());

        IVaultProxy(vault)
            .upgradeToAndCall(
                getImplementationByVersion(newVersion), abi.encodeCall(IUpgradeableVault.upgrade, (newVersion, data))
            );

        emit Migrated(vault, newVersion);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
