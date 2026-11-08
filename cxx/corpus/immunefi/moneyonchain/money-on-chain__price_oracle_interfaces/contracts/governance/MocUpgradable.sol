// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Stoppable } from "../governance/Stoppable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// Import to allow compilation and deploy of ERC1967Proxy
// solhint-disable-next-line no-unused-import
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract MocUpgradable is UUPSUpgradeable, Stoppable {
  /**
    @notice Modifier that protects the function
    @dev You should use this modifier in any function that should be called through
    the governance system or the pauser address
   */
  modifier onlyAuthorizedChangerOrPauser() {
    if (!governor.isAuthorizedChanger(msg.sender) && msg.sender != pauser)
      revert NotAuthorizedChanger();
    _;
  }

  // ------- Initializer -------
  /**
   * @notice contract initializer
   * @param governorAddress_ The address that will define when a change contract is authorized
   * @param pauserAddress_ The address that is authorized to pause this contract
   */
  function __MocUpgradable_init(
    address governorAddress_,
    address pauserAddress_
  ) internal onlyInitializing {
    __UUPSUpgradeable_init();
    __Governed_init(governorAddress_);
    __Stoppable_init_unchained(pauserAddress_, true);
  }

  /**
   * @inheritdoc UUPSUpgradeable
   * @dev checks that the changer that will do the upgrade is currently authorized by governance to makes
   * changes within the system
   * @param newImplementation new implementation contract address(not used)
   */
  function _authorizeUpgrade(address newImplementation) internal override onlyAuthorizedChanger {}

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */

  // Purposely left unused to save some state space to allow for future upgrades
  // slither-disable-next-line unused-state
  uint256[50] private __gap;
}
