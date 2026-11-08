// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IAccessControlManager } from "./interfaces/IAccessControlManager.sol";

/**
 * @title Strata Access Control Contract.
 * @dev The AccessControlled contract is a wrapper around the OpenZeppelin AccessControl contract
 *      It provides a standardized way to control access to methods within the Strata Smart Contract Ecosystem.
 *      The contract allows the owner to set an AccessControlManager contract address.
 */

abstract contract AccessControlled is Initializable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {

    bytes32 public constant PAUSER_ROLE                 = keccak256("PAUSER_ROLE");
    bytes32 public constant UPDATER_CDO_APR_ROLE        = keccak256("UPDATER_CDO_APR_ROLE");
    bytes32 public constant UPDATER_FEED_ROLE           = keccak256("UPDATER_FEED_ROLE");
    bytes32 public constant UPDATER_STRAT_CONFIG_ROLE   = keccak256("UPDATER_STRAT_CONFIG_ROLE");
    bytes32 public constant RESERVE_MANAGER_ROLE        = keccak256("RESERVE_MANAGER_ROLE");
    bytes32 public constant COOLDOWN_WORKER_ROLE        = keccak256("COOLDOWN_WORKER_ROLE");
    bytes32 public constant PROPOSER_CONFIG_ROLE        = keccak256("PROPOSER_CONFIG_ROLE");

    /// @notice Access control manager contract
    IAccessControlManager public acm;

    // @notice Two-step configuration updater contract
    address public twoStepConfigManager;

    uint256[48] private __gap;

    /// @notice Emitted when access control manager contract address is changed
    event NewAccessControlManager(address accessControlManager);
    /// @notice Emitted when two step config manager is changed
    event NewTwoStepConfigManager(address twoStepConfigManager);

    /// @notice Thrown when the action is prohibited by AccessControlManager
    error Unauthorized(address sender, address calledContract, bytes4 sel);
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error ZeroAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyRole(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    modifier onlyTwoStepConfigManager() {
        require(twoStepConfigManager == _msgSender(), "ConfigManagerOnly");
        _;
    }


    function AccessControlled_init(address owner, address accessControlManager) internal onlyInitializing {
        __Ownable_init_unchained(owner);
        __AccessControlled_init_unchained(accessControlManager);
        __ReentrancyGuard_init();
    }

    function __AccessControlled_init_unchained(address accessControlManager) internal onlyInitializing {
        setAccessControlManagerInner(accessControlManager);
    }

    /**
     * @notice Sets the address of AccessControlManager
     * @dev Admin function to set address of AccessControlManager
     * @param accessControlManager_ The new address of the AccessControlManager
     * @custom:event Emits NewAccessControlManager event
     * @custom:access Only Governance
     */
    function setAccessControlManager(address accessControlManager_) external onlyOwner {
        setAccessControlManagerInner(accessControlManager_);
    }

    /**
     * @notice Sets the address of TwoStepConfigManager
     * @dev Admin function to set address of TwoStepConfigManager
     * @param twoStepConfigManager_ The new address of the TwoStepConfigManager
     */
    function setTwoStepConfigManager(address twoStepConfigManager_) external onlyOwner {
        if (twoStepConfigManager_ == address(0)) {
            revert ZeroAddress();
        }
        twoStepConfigManager = twoStepConfigManager_;
        emit NewTwoStepConfigManager(twoStepConfigManager_);
    }

    /**
     * @dev Internal function to set address of AccessControlManager
     * @param accessControlManager The new address of the AccessControlManager
     */
    function setAccessControlManagerInner(address accessControlManager) internal {
        if (accessControlManager == address(0)) {
            revert ZeroAddress();
        }
        acm = IAccessControlManager(accessControlManager);
        emit NewAccessControlManager(accessControlManager);
    }

    /**
     * @notice Reverts if the call is not allowed by AccessControlManager
     * @param sel Method signature
     */
    function _checkAccessAllowed(bytes4 sel) internal view {
        bool isAllowedToCall = acm.isAllowedToCall(msg.sender, sel);

        if (!isAllowedToCall) {
            revert Unauthorized(msg.sender, address(this), sel);
        }
    }

    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!acm.hasRole(role, account)) {
            revert AccessControlUnauthorizedAccount(account, role);
        }
    }
}
