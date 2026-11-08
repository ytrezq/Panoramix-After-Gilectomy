// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IUpgradeableVault {
    error AlreadyInitialized();
    error NotFactory();
    error NotInitialized();
    error InvalidFactoryOwner();

    /**
     * @notice Get the factory's address.
     * @return address of the factory
     */
    function factory() external view returns (address);

    /**
     * @notice Get the vault's version.
     * @return version of the vault
     * @dev Starts from 1.
     */
    function version() external view returns (uint64);

    /**
     * @notice Initialize `UpgradeableVaultProxy` contract by using a given data and setting a particular version and owner.
     * @param initialVersion initial version of the vault
     * @param owner initial owner of the vault
     * @param data some data to use
     */
    function initialize(uint64 initialVersion, address owner, bytes calldata data) external;

    /**
     * @notice Upgrade this vault to a specific newer version using a given data.
     * @param newVersion new version of the vault
     * @param data some data to use
     */
    function upgrade(uint64 newVersion, bytes calldata data) external;
}
