// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "moc-main-latest/contracts/interfaces/IChangeContract.sol";
import { MocVendors } from "moc-main-latest/contracts/vendors/MocVendors.sol";

/**
  @title MocVendorsUpgradeChanger
  @notice This contract is a ChangeContract intended to be used when
  upgrading a MOC UUPS contract, through the Moc upgradeability
  system. This doesn't initialize the upgraded contract, that should be done extending
  this one or taking it as a guide
 */
contract MocVendorsUpgradeChanger is IChangeContract {
    MocVendors public immutable mocVendorsProxy;
    address public immutable MocVendorsNewImplementation;
    uint256 public immutable maxVendorMarkup;
    address[] public vendors;

    /** 
    @notice Constructor
    @param mocVendorsProxy_ Address of the proxy to be upgraded
    @param MocVendorsNewImplementation_ Address of the contract the proxy will delegate to
    @param maxVendorMarkup_ The new maxVendorMarkup to be set in the new implementation
  */
    constructor(
        MocVendors mocVendorsProxy_,
        address MocVendorsNewImplementation_,
        uint256 maxVendorMarkup_,
        address[] memory vendors_
    ) {
        mocVendorsProxy = mocVendorsProxy_;
        MocVendorsNewImplementation = MocVendorsNewImplementation_;
        maxVendorMarkup = maxVendorMarkup_;
        vendors = vendors_;
    }

    /**
    @notice Execute the changes.
    @dev Should be called by the governor, but this contract does not check that explicitly
    because it is not its responsibility in the current architecture
    IMPORTANT: This function should not be overridden, you should only redefine
    _beforeUpgrade and _afterUpgrade methods to use this template
   */
    function execute() external {
        // Store the current markups of the vendors before the upgrade, to set them again after the upgrade
        uint256 vendorsLength = vendors.length;
        uint64[] memory markupBeforeUpgrade = new uint64[](vendorsLength);
        for (uint256 i; i < vendorsLength; i++) {
            uint256 currentMarkup = mocVendorsProxy.vendorMarkup(vendors[i]);
            markupBeforeUpgrade[i] = uint64(currentMarkup > maxVendorMarkup ? maxVendorMarkup : currentMarkup);
        }

        _beforeUpgrade();
        _upgrade();
        _afterUpgrade();

        // Set the same markups to the vendors that were set before the upgrade, capped by the new maxVendorMarkup
        for (uint256 i; i < vendorsLength; i++) {
            mocVendorsProxy.setVendorMarkup(vendors[i], markupBeforeUpgrade[i]);
        }
    }

    /**
    @notice Upgrade the proxy to the newImplementation
    @dev IMPORTANT: This function should not be overridden
   */
    function _upgrade() internal {
        mocVendorsProxy.upgradeTo(MocVendorsNewImplementation);
    }

    /**
    @notice Intended to prepare the system for the upgrade
    @dev This function can be overridden by child changers to upgrade contracts that
    require some preparation before the upgrade
   */
    function _beforeUpgrade() internal {}

    /**
    @notice Intended to do the final tweaks after the upgrade, for example initialize the contract
    @dev This function can be overridden by child changers to upgrade contracts that
    require some changes after the upgrade
   */
    function _afterUpgrade() internal {
        // Set the new maxVendorMarkup in the new implementation
        mocVendorsProxy.setMaxMarkup(maxVendorMarkup);
    }
}
