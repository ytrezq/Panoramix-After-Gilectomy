pragma solidity ^0.5.8;

import "zos-lib/contracts/upgradeability/AdminUpgradeabilityProxy.sol";
import "zos-lib/contracts/upgradeability/ProxyAdmin.sol";
import "../Governance/Governed.sol";

/**
  @title UpgradeDelegator
  @notice Dispatches to the proxyAdmin any call made through the governance system
  @dev Adapter between our governance system and the zeppelinOS proxyAdmin. This is
  needed to be able to upgrade governance through the same system

 */
contract UpgradeDelegator is Governed {
  ProxyAdmin public proxyAdmin;

  /**
    @notice Initialize the contract with the basic settings
    @dev This initialize replaces the constructor but it is not called automatically.
    It is necessary because of the upgradeability of the contracts
    @param _governor Governor address of this system
    @param _proxyAdmin ProxyAdmin that we will forward the call to
   */
  function initialize(address _governor, ProxyAdmin _proxyAdmin) public initializer {
    Governed.initialize(_governor);
    proxyAdmin = _proxyAdmin;
  }

  /**
   * @dev Returns the current implementation of a proxy.
   * This is needed because only the proxy admin can query it.
   * @return The address of the current implementation of the proxy.
   */
  function getProxyImplementation(AdminUpgradeabilityProxy proxy) public view returns (address) {
    return proxyAdmin.getProxyImplementation(proxy);
  }

  /**
   * @dev Returns the admin of a proxy. Only the admin can query it.
   * @return The address of the current admin of the proxy.
   */
  function getProxyAdmin(AdminUpgradeabilityProxy proxy) public view returns (address) {
    return proxyAdmin.getProxyAdmin(proxy);
  }

  /**
   * @dev Changes the admin of a proxy.
   * @param proxy Proxy to change admin.
   * @param newAdmin Address to transfer proxy administration to.
   */
  function changeProxyAdmin(AdminUpgradeabilityProxy proxy, address newAdmin) public onlyAuthorizedChanger {
    proxyAdmin.changeProxyAdmin(proxy, newAdmin);
  }

  /**
   * @dev Upgrades a proxy to the newest implementation of a contract.
   * @param proxy Proxy to be upgraded.
   * @param implementation the address of the Implementation.
   */
  function upgrade(AdminUpgradeabilityProxy proxy, address implementation) public onlyAuthorizedChanger {
    proxyAdmin.upgrade(proxy, implementation);
  }

  /**
   * @dev Upgrades a proxy to the newest implementation of a contract and forwards a function call to it.
   * This is useful to initialize the proxied contract.
   * @param proxy Proxy to be upgraded.
   * @param implementation Address of the Implementation.
   * @param data Data to send as msg.data in the low level call.
   * It should include the signature and the parameters of the function to be called, as described in
   * https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector-and-argument-encoding.
   */
  function upgradeAndCall(AdminUpgradeabilityProxy proxy, address implementation, bytes memory data) public payable onlyAuthorizedChanger {
    proxyAdmin.upgradeAndCall.value(msg.value)(proxy, implementation, data);
  }
}
