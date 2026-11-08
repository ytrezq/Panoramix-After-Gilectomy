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

import {IOndoCompliance} from "contracts/xManager/interfaces/IOndoCompliance.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {IBlocklist} from "contracts/interfaces/IBlocklist.sol";
import {ISanctionsList} from "contracts/external/chainalysis/ISanctionsList.sol";

/**
 * @title  OndoCompliance
 * @author Ondo Finance
 * @notice This contract is responsible for enforcing compliance rules for RWA tokens and
 *         associated systems on the Ondo platform. It allows for setting blocklists and
 *         sanctions lists for RWA tokens.
 *         Roles:
 *          - MASTER_CONFIGURER_ROLE
 *          - RWA_ROLE_MANAGER
 */
contract OndoCompliance is IOndoCompliance, AccessControlEnumerable {
  /// Role to set the blocklist or sanctions list for any RWA token
  bytes32 public constant MASTER_CONFIGURER_ROLE = keccak256("MASTER_CONFIGURER_ROLE");

  /// Role admin for roles for setting blocklists and sanctions lists for specific RWA tokens
  bytes32 public constant RWA_ROLE_MANAGER = keccak256("RWA_ROLE_MANAGER");

  /**
   * @notice Mapping of RWA token address to the role that can set the blocklist or sanctions list
   *         for specific RWA tokens
   */
  mapping(address /*rwaToken*/ => bytes32) public rwaRole;

  /// Mapping of RWA token address to the blocklist contract
  mapping(address => IBlocklist) public rwaTokenToBlocklist;

  /// Mapping of RWA token address to the sanctions list contract
  mapping(address => ISanctionsList) public rwaTokenToSanctionsList;

  /**
   * @notice Emitted when the role is set for a RWA token
   * @param  rwaToken The RWA token address
   * @param  role     The role that was set - keccak256 hash of the RWA token address
   */
  event RWARoleSet(address indexed rwaToken, bytes32 role);

  /**
   * @notice Emitted when the blocklist is set for a RWA token
   * @param  rwaToken     The RWA token address for which the blocklist was set
   * @param  oldBlocklist The old blocklist contract
   * @param  newBlocklist The new blocklist contract
   */
  event BlocklistSet(address indexed rwaToken, IBlocklist oldBlocklist, IBlocklist newBlocklist);

  /**
   * @notice Emitted when the sanctions list is set for a RWA token
   * @param  rwaToken         The RWA token address for which the sanctions list was set
   * @param  oldSanctionsList The old sanctions list contract
   * @param  newSanctionsList The new sanctions list contract
   */
  event SanctionsListSet(
    address indexed rwaToken, ISanctionsList oldSanctionsList, ISanctionsList newSanctionsList
  );

  /// Error thrown when a user is blocked via the blocklist
  error UserBlocked();

  /// Error thrown when a user is sanctioned via the sanctions list
  error UserSanctioned();

  /// Error thrown when trying to set an RWA token address of 0x0
  error RWAAddressCannotBeZero();

  /// Error thrown when trying to set configure an RWA token without the required role
  error MissingRWAOrMasterConfigurerRole();

  /// @param admin The address that will be granted the default admin role
  constructor(address admin) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
  }

  /**
   * @notice Check if a user is compliant with the RWA token's compliance rules
   * @param  rwaToken The RWA token address
   * @param  user     The user address
   * @dev    Reverts if the user is not compliant. Does not revert for unsupported tokens.
   */
  function checkIsCompliant(address rwaToken, address user) external view override {
    if (
      address(rwaTokenToBlocklist[rwaToken]) != address(0)
        && rwaTokenToBlocklist[rwaToken].isBlocked(user)
    ) revert UserBlocked();

    if (
      address(rwaTokenToSanctionsList[rwaToken]) != address(0)
        && rwaTokenToSanctionsList[rwaToken].isSanctioned(user)
    ) revert UserSanctioned();
  }

  /**
   * @notice Set the blocklist for a given RWA token
   * @param  rwaToken  The RWA token address
   * @param  blocklist The blocklist contract
   */
  function setBlocklist(address rwaToken, IBlocklist blocklist) external {
    if (!(hasRole(rwaRole[rwaToken], _msgSender())
          || hasRole(MASTER_CONFIGURER_ROLE, _msgSender()))) revert MissingRWAOrMasterConfigurerRole();
    if (rwaToken == address(0)) revert RWAAddressCannotBeZero();
    emit BlocklistSet(rwaToken, rwaTokenToBlocklist[rwaToken], blocklist);

    rwaTokenToBlocklist[rwaToken] = blocklist;
  }

  /**
   * @notice Set the sanctions list for a given RWA token
   * @param  rwaToken      The RWA token address
   * @param  sanctionsList The sanctions list contract
   */
  function setSanctionsList(address rwaToken, ISanctionsList sanctionsList) external {
    if (!(hasRole(rwaRole[rwaToken], _msgSender())
          || hasRole(MASTER_CONFIGURER_ROLE, _msgSender()))) revert MissingRWAOrMasterConfigurerRole();
    if (rwaToken == address(0)) revert RWAAddressCannotBeZero();
    emit SanctionsListSet(rwaToken, rwaTokenToSanctionsList[rwaToken], sanctionsList);

    rwaTokenToSanctionsList[rwaToken] = sanctionsList;
  }

  /**
   * @notice Set the role for a RWA token
   * @param  rwaToken The RWA token address
   * @dev    This role is computed as the keccak256 hash of the RWA token address.
   */
  function setRWARole(address rwaToken) external onlyRole(RWA_ROLE_MANAGER) {
    if (rwaToken == address(0)) revert RWAAddressCannotBeZero();
    bytes32 role = keccak256(abi.encodePacked(rwaToken));
    _setRoleAdmin(role, RWA_ROLE_MANAGER);
    rwaRole[rwaToken] = role;

    emit RWARoleSet(rwaToken, role);
  }
}
