// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IConcreteFactory {
    error AlreadyBlocked();
    error AlreadyApproved();
    error InvalidImplementation();
    error InvalidVersion();
    error NotOwner();
    error NotRegisteredVault();
    error OldVersion();
    error ImplementationBlocked();
    error CanNotMigrate();
    error InvalidFactoryOwner();
    error VaultAlreadyRegistered();
    error ZeroAddress();
    error InvalidVaultAddress();
    error InvalidDataLength();

    /**
     * @notice Emitted when a new vault is deployed.
     * @param vault address of the new vault
     * @param version version of the new vault
     * @param owner address of the owner of the new vault
     */
    event Deployed(address indexed vault, uint64 indexed version, address indexed owner);

    /**
     * @notice Emitted when a new implementation is approved.
     * @param implementation address of the new implementation
     */
    event ApprovedImplementation(address indexed implementation);

    /**
     * @notice Emitted when an implementation is blocked.
     * @param version version of the implementation that was blocked
     */
    event Blocked(uint64 indexed version);

    /**
     * @notice Emitted when a version is set as migratable to another version.
     * @param fromVersion version that was set as migratable
     * @param toVersion version that was set as migratable
     */
    event Migratable(uint64 indexed fromVersion, uint64 indexed toVersion);

    /**
     * @notice Emitted when an vault is migrated to a new version.
     * @param vault address of the vault
     * @param newVersion new version of the vault
     */
    event Migrated(address indexed vault, uint64 newVersion);

    /**
     * @notice Emitted when a vault is registered with the factory.
     * @param vault address of the vault that was registered
     */
    event VaultRegistered(address indexed vault);

    /**
     * @notice Approve a new implementation for using to deploy a proxy.
     * @param implementation address of the new implementation
     */
    function approveImplementation(address implementation) external;

    /**
     * @notice Block an implementation.
     * @param version version of the implementation to block
     */
    function blockImplementation(uint64 version) external;

    /**
     * @notice Set a version as migratable to another version.
     * @param fromVersion version to set as migratable
     * @param toVersion version to set as migratable
     */
    function setMigratable(uint64 fromVersion, uint64 toVersion) external;

    /**
     * @notice Deploy a new proxy vault.
     * @param version vault's version to use
     * @param owner initial owner of the vault
     * @param data initial data for the vault creation
     * @return address of the vault
     * @dev CREATE2 salt is constructed from the given parameters.
     */
    function create(uint64 version, address owner, bytes calldata data) external returns (address);

    /**
     * @notice Deploy a new proxy vault.
     * @param version vault's version to use
     * @param owner initial owner of the vault
     * @param data initial data for the vault creation
     * @return address of the vault
     * @dev CREATE2 salt is constructed from the given parameters.
     */
    function create(uint64 version, address owner, bytes calldata data, bytes32 salt) external returns (address);

    /**
     * @notice Predict the address of a vault that would be deployed with the given parameters.
     * @param version vault's version to use
     * @param ownerAddr initial owner of the vault
     * @param data initial data for the vault creation
     * @return predicted address of the vault
     */
    function predictVaultAddress(uint64 version, address ownerAddr, bytes calldata data) external view returns (address);

    /**
     * @notice Predict the address of a vault that would be deployed with the given parameters.
     * @param version vault's version to use
     * @param ownerAddr initial owner of the vault
     * @param data initial data for the vault creation
     * @param salt for CREATE2 deployment.
     * @return predicted address of the vault
     */
    function predictVaultAddress(uint64 version, address ownerAddr, bytes calldata data, bytes32 salt)
        external
        view
        returns (address);

    /**
     * @notice Upgrade a vault to a new implementation version.
     * @param vault address of the vault to upgrade
     * @param newVersion new version to upgrade to
     * @param data upgrade data
     * @dev Only the vault owner can initiate upgrade. The new version must be higher than the current version.
     */
    function upgrade(address vault, uint64 newVersion, bytes calldata data) external;

    /**
     * @notice Upgrade multiple vaults to a new implementation version in a single transaction.
     * @param vaultAddresses array of vault addresses to upgrade
     * @param newVersion new version to upgrade all vaults to
     * @param data upgrade data to use for all vault upgrades
     * @dev Only the vault owners can initiate upgrade for their respective vaults. The new version must be higher than the current version for each vault.
     */
    function batchUpgrade(address[] calldata vaultAddresses, uint64 newVersion, bytes[] calldata data) external;

    /**
     * @notice Get the last available version.
     * @return version of the last implementation
     * @dev If zero, no implementations are approved.
     */
    function lastVersion() external view returns (uint64);

    /**
     * @notice Get the implementation for a given version.
     * @param version version to get the implementation for
     * @return address of the implementation
     * @dev Reverts when an invalid version.
     */
    function getImplementationByVersion(uint64 version) external view returns (address);

    /**
     * @notice Get if an implementation is blocked
     * @param version version to check
     * @return bool true if the implementation is blocked
     */
    function isBlocked(uint64 version) external view returns (bool);

    /**
     * @notice Get if a version is migratable to another version
     * @param fromVersion version to check
     * @param toVersion version to check
     * @return bool true if the version is migratable
     */
    function isMigratable(uint64 fromVersion, uint64 toVersion) external view returns (bool);

    /**
     * @notice Check if a vault was deployed by this factory
     * @param vault The vault address to check
     * @return True if the vault was deployed by this factory, false otherwise
     */
    function isRegisteredVault(address vault) external view returns (bool);

    /**
     * @notice Register a previously deployed vault with this factory for management
     * @param vault The vault address to register
     * @dev Only the factory owner can register vaults. The vault must be a valid upgradeable vault.
     */
    function registerVault(address vault) external;
}
