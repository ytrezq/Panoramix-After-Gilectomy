// SPDX-License-Identifier: BUSL-1.1
/*
      ▄▄█████████▄
   ╓██▀└ ,╓▄▄▄, '▀██▄
  ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
  ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
   ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
      ╙▀▀██████R⌐
 */
pragma solidity 0.8.33;

import {IOndoIDRegistry} from "contracts/xManager/interfaces/IOndoIDRegistry.sol";
import {
  Initializable
} from "contracts/external/openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {
  ContextUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {
  AccessControlEnumerableUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

/**
 * @title  OndoIDRegistry
 * @author Ondo Finance
 * @notice The OndoRegistry serves as both a repository for user IDs and a whitelist
 *         for users who are allowed to interact with the RWAManagers. IDs are stored on a per-RWA
 *         and per-user basis, and a single ID can be associated with multiple user addresses. IDs
 *         may be set by the RWA token admin or a master configurer. A master configurer can set
 *         IDs for any RWA token, while an RWA token admin can only set IDs for a specific RWA
 *         token. RWA token admin roles are generated dynamically as needed via the keccak256
 *         hash of the RWA token address.
 */
contract OndoIDRegistry is
  Initializable,
  ContextUpgradeable,
  AccessControlEnumerableUpgradeable,
  IOndoIDRegistry
{
  /// Role to set a user ID for any RWA token
  bytes32 public constant MASTER_CONFIGURER_ROLE = keccak256("MASTER_CONFIGURER_ROLE");

  /// Role to setup and manage RWA token roles
  bytes32 public constant RWA_ROLE_MANAGER = keccak256("RWA_ROLE_MANAGER");

  /// Mapping of RWA token address to role with permissions for the RWA token
  mapping(address /*rwaToken*/ => bytes32) public rwaRole;

  /// Mapping of RWA token address and user address to the user ID
  mapping(address /*rwaToken*/ => mapping(address /* user */ => bytes32 /* userID */)) public
    userIDs;

  /**
   * @notice Emitted when a user ID is set for a given RWA token and user address
   * @param  rwaToken The RWA token address for which the ID was set
   * @param  user     The user address for which the ID was set
   * @param  userID   The ID that was set, or 0x0 if the ID was removed
   */
  event UserIDSet(address indexed rwaToken, address indexed user, bytes32 indexed userID);

  /**
   * @notice Emitted when the role that can set user IDs for a given RWA token is set
   * @param  rwaToken The RWA token address for which the role was set
   * @param  role     The role that was set - keccak256 hash of the RWA token address
   */
  event RWARoleSet(address indexed rwaToken, bytes32 role);

  /// Error thrown when the RWA token address is 0x0
  error RWAAddressCannotBeZero();

  /// Error thrown when attempting to remove a user that is not registered
  error UserNotRegistered();

  /// Error thrown when the user address is 0x0
  error AddressCannotBeZero();

  /// Error thrown when the user address is already associated with the user ID
  error AddressAlreadyAssociated();

  /// Error thrown when attempting to set a user ID to 0x0
  error InvalidUserId();

  /// Error thrown when the caller does not have the required role to set a user ID
  error MissingRWAOrMasterConfigurerRole();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    // Disable the constructor to prevent initializing the contract directly.
    _disableInitializers();
  }

  /**
   * @notice Initializes the contract with the provided admin address
   * @param  admin The address to be set as the default admin
   */
  function initialize(address admin) public initializer {
    __AccessControlEnumerable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
  }

  /**
   * @notice Retrieves the user ID associated with an address and RWA tokens
   * @param  rwaToken The RWA token address associated with the user ID
   * @param  user     The user address to retrieve the ID for
   * @return userID   The registered user ID
   * @dev    Will return 0x0 if the user is not registered. 0x0 is an invalid ID.
   */
  function getRegisteredID(address rwaToken, address user)
    external
    view
    override
    returns (bytes32 userID)
  {
    if (rwaToken == address(0)) revert RWAAddressCannotBeZero();
    if (user == address(0)) revert AddressCannotBeZero();
    return userIDs[rwaToken][user];
  }

  /**
   * @notice Sets the user ID for a given rwaToken and list of user addresses
   * @param  rwaToken      The RWA token address associated with the ID
   * @param  userAddresses The user addresses associated with the ID
   * @param  newUserID     The new ID
   * @dev    Reverts if any of the user addresses are already associated with the new ID
   */
  function setUserID(address rwaToken, address[] calldata userAddresses, bytes32 newUserID)
    external
  {
    if (!(hasRole(rwaRole[rwaToken], _msgSender())
          || hasRole(MASTER_CONFIGURER_ROLE, _msgSender()))) {
      revert MissingRWAOrMasterConfigurerRole();
    }

    if (rwaToken == address(0)) revert RWAAddressCannotBeZero();
    if (newUserID == 0) revert InvalidUserId();
    for (uint256 i = 0; i < userAddresses.length; ++i) {
      if (userAddresses[i] == address(0)) revert AddressCannotBeZero();

      bytes32 previousUserId = userIDs[rwaToken][userAddresses[i]];

      if (previousUserId == newUserID) revert AddressAlreadyAssociated();

      userIDs[rwaToken][userAddresses[i]] = newUserID;

      emit UserIDSet(rwaToken, userAddresses[i], newUserID);
    }
  }

  /**
   * @notice Removes provided addresses from the registry
   * @param  rwaToken      The RWA token address associated addresses
   * @param  userAddresses The user addresses to remove
   */
  function removeUserAddresses(address rwaToken, address[] calldata userAddresses) external {
    if (!(hasRole(rwaRole[rwaToken], _msgSender())
          || hasRole(MASTER_CONFIGURER_ROLE, _msgSender()))) revert MissingRWAOrMasterConfigurerRole();

    if (rwaToken == address(0)) revert RWAAddressCannotBeZero();

    for (uint256 i = 0; i < userAddresses.length; ++i) {
      if (userAddresses[i] == address(0)) revert AddressCannotBeZero();

      bytes32 userID = userIDs[rwaToken][userAddresses[i]];
      if (userID == 0) revert UserNotRegistered();

      delete userIDs[rwaToken][userAddresses[i]];

      emit UserIDSet(rwaToken, userAddresses[i], 0);
    }
  }

  /**
   * @notice Sets the role that can set user IDs for a given RWA token.
   * @param  rwaToken The RWA token address for which we wish to set the role.
   * @dev    The role is automatically computed as the keccak256 hash of the RWA token address.
   */
  function setRWARole(address rwaToken) external onlyRole(RWA_ROLE_MANAGER) {
    if (rwaToken == address(0)) revert RWAAddressCannotBeZero();
    bytes32 role = keccak256(abi.encodePacked(rwaToken));
    _setRoleAdmin(role, RWA_ROLE_MANAGER);
    rwaRole[rwaToken] = role;

    emit RWARoleSet(rwaToken, role);
  }
}
