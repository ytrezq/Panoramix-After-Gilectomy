// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UpgradeableVault} from "../../../src/common/UpgradeableVault.sol";
import {IUpgradeableVault} from "../../../src/interface/IUpgradeableVault.sol";
import {VaultProxy} from "../../../src/factory/VaultProxy.sol";

contract UpgradeableVaultUnitTest is Test {
    UpgradeableVaultImpl public upgradeableVault;
    address public owner = makeAddr("owner");
    address public protocolConfig = makeAddr("protocolConfig");
    bytes public data = "";

    function setUp() public {
        upgradeableVault = new UpgradeableVaultImpl(address(this));
    }

    function testInitializeRevertsIfNotFactory() public {
        vm.expectRevert(abi.encodeWithSelector(IUpgradeableVault.NotFactory.selector));
        vm.prank(address(1));
        new VaultProxy(address(upgradeableVault), abi.encodeCall(IUpgradeableVault.initialize, (1, owner, data)));
    }
}

contract UpgradeableVaultImpl is UpgradeableVault {
    constructor(address factory) UpgradeableVault(factory) {}
}
