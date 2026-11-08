// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "../../interfaces/IChangeContract.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
  @title UpgraderUUPSChangerTemplate
  @notice This contract is a ChangeContract intended to be used when
  upgrading a MOC UUPS contract, through the Moc upgradeability
  system. This doesn't initialize the upgraded contract, that should be done extending
  this one or taking it as a guide
 */
contract UpgraderUUPSChangerTemplate is IChangeContract {
    UUPSUpgradeable public immutable PROXY;
    address public immutable NEW_IMPLEMENTATION;

    /** 
    @notice Constructor
    @param proxy_ Address of the proxy to be upgraded
    @param newImplementation_ Address of the contract the proxy will delegate to
  */
    constructor(UUPSUpgradeable proxy_, address newImplementation_) {
        PROXY = proxy_;
        NEW_IMPLEMENTATION = newImplementation_;
    }

    /**
    @notice Execute the changes.
    @dev Should be called by the governor, but this contract does not check that explicitly
    because it is not its responsibility in the current architecture
    IMPORTANT: This function should not be overridden, you should only redefine
    _beforeUpgrade and _afterUpgrade methods to use this template
   */
    function execute() external {
        _beforeUpgrade();
        _upgrade();
        _afterUpgrade();
    }

    /**
    @notice Upgrade the proxy to the newImplementation
    @dev IMPORTANT: This function should not be overridden
   */
    function _upgrade() internal {
        PROXY.upgradeTo(NEW_IMPLEMENTATION);
    }

    /**
    @notice Intended to prepare the system for the upgrade
    @dev This function can be overridden by child changers to upgrade contracts that
    require some preparation before the upgrade
   */
    function _beforeUpgrade() internal virtual {}

    /**
    @notice Intended to do the final tweaks after the upgrade, for example initialize the contract
    @dev This function can be overridden by child changers to upgrade contracts that
    require some changes after the upgrade
   */
    function _afterUpgrade() internal virtual {}
}
