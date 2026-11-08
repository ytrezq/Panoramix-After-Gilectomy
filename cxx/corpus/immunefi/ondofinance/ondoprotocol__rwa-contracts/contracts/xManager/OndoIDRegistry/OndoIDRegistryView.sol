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

import {IOndoIDRegistryView} from "contracts/xManager/interfaces/IOndoIDRegistryView.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {IOndoIDRegistry} from "contracts/xManager/interfaces/IOndoIDRegistry.sol";

/**
 * @title  OndoIDRegistryView
 * @author Ondo Finance
 * @notice The OndoIDRegistryView contract is a read-only view of the OndoIDRegistry contract
 *         that allows for querying the registered ID of a user and checking if a user is registered.
 * @dev    This contracts exist for ease of future changes in the registry implementation and
 *         backwards compatibility with existing systems. All registry clients should point to
 *         contract rather than going directly to the registry.
 */
contract OndoIDRegistryView is IOndoIDRegistryView, AccessControlEnumerable {
  /// The OndoIDRegistry contract
  IOndoIDRegistry public ondoIDRegistry;

  /// Mapping of KYC requirement group to RWA token address
  mapping(uint256 => address) public kycRequirementGroupToRwaToken;

  /**
   * @notice Emitted when the OndoIDRegistry contract address is set
   * @param  oldOndoIDRegistry The old OndoIDRegistry contract address
   * @param  newOndoIDRegistry The new OndoIDRegistry contract address
   */
  event OndoRegistrySet(address oldOndoIDRegistry, address newOndoIDRegistry);

  /**
   * @notice Emitted when the RWA token address for a KYC requirement group is set
   * @param  kycRequirementGroup The KYC requirement group
   * @param  rwaToken The RWA token address
   */
  event KYCRequirementGroupSet(uint256 kycRequirementGroup, address rwaToken);

  /// Error emitted when attempting to set the OndoIDRegistry address to zero
  error OndoIDRegistryAddressCannotBeZero();

  /// Error emitted when attempting to set a KYC requirement group to a zero RWA token address
  error RWAAddressCannotBeZero();

  /// Error emitted when attempting to set the rwaToken to KYC requirement group 0
  error InvalidKYCRequirementGroup();

  /**
   * @param _ondoIDRegistry The address of the OndoIDRegistry contract
   * @dev   The caller of this constructor will be granted the DEFAULT_ADMIN_ROLE
   */
  constructor(address _ondoIDRegistry) {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    ondoIDRegistry = IOndoIDRegistry(_ondoIDRegistry);
  }

  /**
   * @notice Get the registered ID of a user for a given RWA token
   * @param  rwaToken The RWA token address
   * @param  user     The user address
   * @return userID   The registered ID of the user
   */
  function getRegisteredID(address rwaToken, address user)
    external
    view
    override
    returns (bytes32 userID)
  {
    return ondoIDRegistry.getRegisteredID(rwaToken, user);
  }

  /**
   * @notice Check if a user is registered for a given RWA token
   * @param  rwaToken     The RWA token address
   * @param  user         The user address
   * @return isRegistered True if the user is registered, false otherwise
   */
  function isRegistered(address rwaToken, address user) external view override returns (bool) {
    return ondoIDRegistry.getRegisteredID(rwaToken, user) != bytes32(0);
  }

  /**
   * @notice Get the KYC status of a user for a given KYC requirement group
   * @param  kycRequirementGroup The KYC requirement group
   * @param  account             The user address
   * @return True if the user is KYC compliant, false otherwise
   */
  function getKYCStatus(uint256 kycRequirementGroup, address account)
    external
    view
    override
    returns (bool)
  {
    if (kycRequirementGroupToRwaToken[kycRequirementGroup] == address(0)) {
      revert InvalidKYCRequirementGroup();
    }
    return ondoIDRegistry.getRegisteredID(
      kycRequirementGroupToRwaToken[kycRequirementGroup], account
    ) != bytes32(0);
  }

  /**
   * @notice Set the OndoIDRegistry contract address.
   * @param  _ondoIDRegistry The address of the OndoIDRegistry contract.
   */
  function setOndoRegistry(address _ondoIDRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoIDRegistry == address(0)) {
      revert OndoIDRegistryAddressCannotBeZero();
    }
    emit OndoRegistrySet(address(ondoIDRegistry), _ondoIDRegistry);
    ondoIDRegistry = IOndoIDRegistry(_ondoIDRegistry);
  }

  /**
   * @notice Set the RWA token address for a KYC requirement group
   * @param  kycRequirementGroup The KYC requirement group
   * @param  rwaToken            The RWA token address
   */
  function setKYCRequirementGroupToRwaToken(uint256 kycRequirementGroup, address rwaToken)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (rwaToken == address(0)) {
      revert RWAAddressCannotBeZero();
    }
    if (kycRequirementGroup == 0) revert InvalidKYCRequirementGroup();
    kycRequirementGroupToRwaToken[kycRequirementGroup] = rwaToken;

    emit KYCRequirementGroupSet(kycRequirementGroup, rwaToken);
  }
}
