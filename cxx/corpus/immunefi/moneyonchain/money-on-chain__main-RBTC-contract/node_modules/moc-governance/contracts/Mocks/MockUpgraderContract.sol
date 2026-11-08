pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "../ChangersTemplates/UpgraderTemplate.sol";
import "./MockUpgraded.sol";

contract MockUpgraderContract is UpgraderTemplate {

  constructor(AdminUpgradeabilityProxy _proxy, UpgradeDelegator _upgradeDelegator, address _newImplementation)
  public
  UpgraderTemplate(_proxy, _upgradeDelegator, _newImplementation){
  }

  function _afterUpgrade() internal {
    MockUpgraded upgradedProxy = MockUpgraded(address(proxy));

    upgradedProxy.initialize2();

  }
}