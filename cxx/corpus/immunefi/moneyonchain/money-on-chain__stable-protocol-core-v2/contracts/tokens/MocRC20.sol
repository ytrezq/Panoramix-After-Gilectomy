// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IMocRC20 } from "../interfaces/IMocRC20.sol";
import { IGovernor, Governed } from "../governance/Governed.sol";
/* solhint-disable-next-line max-line-length */
import { AccessControlEnumerableUpgradeable, AccessControlUpgradeable, IAccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title MocRC20
 * @notice Base Moc ERC20 Token: burn, mint. It can be both Pegs and Collateral Tokens.
 * @dev ERC20 like token that allows roles allowed contracts to mint and burn (destroyed) any token.
 */
contract MocRC20 is IMocRC20, AccessControlEnumerableUpgradeable, ERC20Upgradeable, UUPSUpgradeable, Governed {
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ------- Custom Errors -------
    error NotUniqueRole(bytes32 role);
    error NotYourself();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice contract initializer
     * @dev grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `BURNER_ROLE` to `admin_` address.
     * @param name_ RC20 token name
     * @param symbol_ RC20 token symbol
     * @param admin_ address of the admin
     * @param governor_ address of the governor
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address admin_,
        IGovernor governor_
    ) external initializer {
        __MocRC20_init(name_, symbol_, admin_, governor_);
    }

    /**
     * @notice contract initializer
     * @dev grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `BURNER_ROLE` to `admin_` address.
     * @param name_ RC20 token name
     * @param symbol_ RC20 token symbol
     * @param admin_ address of the admin
     * @param governor_ address of the governor
     */
    function __MocRC20_init(
        string memory name_,
        string memory symbol_,
        address admin_,
        IGovernor governor_
    ) internal onlyInitializing {
        __ERC20_init(name_, symbol_);
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();
        __Governed_init(address(governor_));
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(BURNER_ROLE, admin_);
    }

    /**
     * @inheritdoc UUPSUpgradeable
     * @dev checks that the changer that will do the upgrade is currently authorized by governance to makes
     * changes within the system
     * @param newImplementation new implementation contract address(not used)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyAuthorizedChanger {}

    /**
     * @dev Creates `amount` new tokens for `to`.
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount) external virtual onlyRole(MINTER_ROLE) returns (bool) {
        _mint(to, amount);
        return true;
    }

    /**
     * @dev Burns a specific `amount` of tokens for `to`.
     * * See {ERC20-_burn}.
     * Requirements:
     *
     * - the caller must have the `BURNER_ROLE`.
     */
    function burn(address to, uint256 amount) external virtual onlyRole(BURNER_ROLE) {
        _burn(to, amount);
    }

    /**
     * @dev Grants all `roles` to `account` while sender renounces to all ``role``
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     * - no one else must have any other role
     *
     * May emit a {RoleGranted x3, RoleRevoked x3} event.
     */
    function transferAllRoles(address account) public virtual onlyRole(getRoleAdmin(DEFAULT_ADMIN_ROLE)) {
        if (account == msg.sender) revert NotYourself();
        // One the new admin account has roles
        if (getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 1) revert NotUniqueRole(DEFAULT_ADMIN_ROLE);
        if (getRoleMemberCount(MINTER_ROLE) != 1) revert NotUniqueRole(MINTER_ROLE);
        if (getRoleMemberCount(BURNER_ROLE) != 1) revert NotUniqueRole(BURNER_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, account);
        _grantRole(MINTER_ROLE, account);
        _grantRole(BURNER_ROLE, account);
        _revokeRole(MINTER_ROLE, msg.sender);
        _revokeRole(BURNER_ROLE, msg.sender);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role  OR
     *   the caller must have be an authorized Governance changer.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(
        bytes32 role,
        address account
    ) public virtual override(AccessControlUpgradeable, IAccessControlUpgradeable) {
        _verifyRoleManagementPrivilege(role);
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role  OR
     *   the caller must have be an authorized Governance changer.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(
        bytes32 role,
        address account
    ) public virtual override(AccessControlUpgradeable, IAccessControlUpgradeable) {
        _verifyRoleManagementPrivilege(role);
        _revokeRole(role, account);
    }

    // ------- Internal Functions -------

    function _verifyRoleManagementPrivilege(bytes32 role) internal view {
        if (!governor.isAuthorizedChanger(msg.sender) && !hasRole(getRoleAdmin(role), msg.sender))
            revert NotAuthorizedChanger();
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
