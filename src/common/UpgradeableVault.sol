// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

/**
 * @title AbstractUpgradeableVault
 * @notice Abstract upgradeable base for Concrete vault implementations.
 *         Provides initializer pattern, ownership, and reentrancy guards.
 *
 * @author Blueprint Finance
 * @custom:protocol Concrete Earn V2
 * @custom:source on request
 * @custom:audits on request
 * @custom:license  AGPL-3.0
 */

// ─────────────────────────────────────────────────────────────────────────────
// External dependencies
// ─────────────────────────────────────────────────────────────────────────────
import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Protocol-facing interfaces
// ─────────────────────────────────────────────────────────────────────────────
import {IUpgradeableVault} from "../interface/IUpgradeableVault.sol";

abstract contract UpgradeableVault is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IUpgradeableVault {
    address public immutable factory;

    constructor(address factoryAddr) {
        _disableInitializers();

        factory = factoryAddr;
    }

    modifier notInitialized() {
        if (_getInitializedVersion() != 0) {
            revert AlreadyInitialized();
        }

        _;
    }

    /**
     * @inheritdoc IUpgradeableVault
     */
    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /**
     * @inheritdoc IUpgradeableVault
     */
    function initialize(uint64 initialVersion, address owner_, bytes calldata data)
        external
        notInitialized
        reinitializer(initialVersion)
    {
        require(_msgSender() == factory, NotFactory());

        __ReentrancyGuard_init();

        __Ownable_init(owner_);

        _initialize(initialVersion, owner_, data);
    }

    /**
     * @inheritdoc IUpgradeableVault
     */
    function upgrade(uint64 newVersion, bytes calldata data) external nonReentrant reinitializer(newVersion) {
        require(_msgSender() == factory, NotFactory());

        _upgrade(_getInitializedVersion(), newVersion, data);
    }

    /**
     *
     * @param initialVersion initial implementation version from the factory
     * @param owner vault proxy owner address
     * @param data arbitrary data used to initialize a proxy implementation
     */
    function _initialize(uint64 initialVersion, address owner, bytes memory data) internal virtual {}

    /**
     *
     * @param oldVersion vault proxy old implementation version
     * @param newVersion vault proxy new implementation version
     * @param data arbitrary data that will be used on the new `newImplementation.upgrade()` function to execute the upgrade flow
     */
    function _upgrade(uint64 oldVersion, uint64 newVersion, bytes calldata data) internal virtual {}
}
