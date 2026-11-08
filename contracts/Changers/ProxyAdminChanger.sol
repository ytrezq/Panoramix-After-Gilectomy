pragma solidity ^0.5.8;

import "zos-lib/contracts/upgradeability/ProxyAdmin.sol";
import "../Governance/ChangeContract.sol";
import "../Upgradeability/UpgradeDelegator.sol";

/**
  @title ProxyAdminChanger
  @notice This contract allows updating the ProxyAdmin of a proxy contract.
 */
contract ProxyAdminChanger is ChangeContract {
  AdminUpgradeabilityProxy public proxy;
  UpgradeDelegator public upgradeDelegator;
  address public newProxyAdmin;

  /**
    @notice Constructor
    @param _proxy Address of the proxy to be upgraded
    @param _upgradeDelegator Address of the old upgradeDelegator in charge of that proxy.
    @param _newProxyAdmin Address of the new AdminProxy with new upgradeDelegator.
  */
  constructor(AdminUpgradeabilityProxy _proxy, UpgradeDelegator _upgradeDelegator, address _newProxyAdmin) public {
    proxy = _proxy;
    upgradeDelegator = _upgradeDelegator;
    newProxyAdmin = _newProxyAdmin;
  }
  /**
    @notice Execute the changes.
   */
  function execute() external {
    upgradeDelegator.changeProxyAdmin(proxy, newProxyAdmin);
  }
}
