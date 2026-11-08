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

import {ProxyAdmin} from "contracts/external/openzeppelin/contracts/proxy/ProxyAdmin.sol";
import {OndoIDRegistry} from "contracts/xManager/OndoIDRegistry/OndoIDRegistry.sol";
import {
  TransparentUpgradeableProxy
} from "contracts/external/openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

/**
 * @title  OndoIDRegistryFactory
 * @author Ondo Finance
 * @notice This contract serves as a Factory for the upgradable OndoIDRegistry contract.
 *         Upon calling `deployOndoIDRegistry` the `guardian` address (set in constructor) will
 *         deploy the following:
 *         1) OndoIDRegistry - The implementation contract with the initializer
 *                             disabled
 *         2) ProxyAdmin - OZ ProxyAdmin contract, used to upgrade the proxy instance.
 *                         Owner is set to `guardian` address.
 *         3) TransparentUpgradeableProxy - OZ, proxy contract. Admin is set to
 *                                          `address(proxyAdmin)`. `_logic' is set to
 *                                          `address(OndoIDRegistry)`.
 */
contract OndoIDRegistryFactory {
  /// The bytes32 value of the default admin role
  bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

  /// The address of the guardian
  address internal immutable GUARDIAN;
  /// The OndoIDRegistry implementation contract
  OndoIDRegistry public ondoIDRegistryImplementation;
  /// The Openzeppelin ProxyAdmin contract
  ProxyAdmin public ondoIDRegistryProxyAdmin;
  /// The Openzeppelin TransparentUpgradeableProxy contract
  TransparentUpgradeableProxy public ondoIDRegistryProxy;

  /// Boolean to indicate if the contract has been initialized
  bool public initialized = false;

  /**
   * @notice Event emitted when upgradable OndoIDRegistry is deployed
   * @param  proxy          The address for the proxy contract
   * @param  proxyAdmin     The address for the proxy admin contract
   * @param  implementation The address for the implementation contract
   */
  event OndoIDRegistryDeployed(address proxy, address proxyAdmin, address implementation);

  /**
   * @param _guardian The address of the guardian
   * @dev   The guardian address will likely be a multisig
   */
  constructor(address _guardian) {
    GUARDIAN = _guardian;
  }

  /**
   * @notice Deploys an upgradable instance of OndoIDRegistry
   * @param  admin   The address of the admin
   * @return address The address of the proxy contract
   * @return address The address of the proxyAdmin contract
   * @return address The address of the implementation contract
   * @dev    1) Will grant DEFAULT_ADMIN to `admin` address, as specified in OndoIDRegistry
   *            constructor.
   *         2) Will transfer ownership of the proxyAdmin to `admin` address.
   */
  function deployOndoIDRegistry(address admin)
    external
    onlyGuardian
    returns (address, address, address)
  {
    require(!initialized, "OndoIDRegistryFactory: OndoIDRegistry already deployed");
    ondoIDRegistryImplementation = new OndoIDRegistry();
    ondoIDRegistryProxyAdmin = new ProxyAdmin();
    ondoIDRegistryProxy = new TransparentUpgradeableProxy(
      address(ondoIDRegistryImplementation), address(ondoIDRegistryProxyAdmin), ""
    );
    OndoIDRegistry ondoIDRegistryProxied = OndoIDRegistry(address(ondoIDRegistryProxy));
    ondoIDRegistryProxied.initialize(admin);

    ondoIDRegistryProxyAdmin.transferOwnership(admin);
    assert(ondoIDRegistryProxyAdmin.owner() == admin);
    initialized = true;
    emit OndoIDRegistryDeployed(
      address(ondoIDRegistryProxy),
      address(ondoIDRegistryProxyAdmin),
      address(ondoIDRegistryImplementation)
    );
    return (
      address(ondoIDRegistryProxy),
      address(ondoIDRegistryProxyAdmin),
      address(ondoIDRegistryImplementation)
    );
  }

  /// Modifier to check if the caller is the guardian
  modifier onlyGuardian() {
    require(msg.sender == GUARDIAN, "OndoIDRegistryFactory: You are not the Guardian");
    _;
  }
}
