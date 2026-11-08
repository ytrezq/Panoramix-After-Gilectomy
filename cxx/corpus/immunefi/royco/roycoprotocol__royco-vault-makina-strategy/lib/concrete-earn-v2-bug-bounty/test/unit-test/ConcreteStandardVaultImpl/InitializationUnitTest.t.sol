// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ConcreteStandardVaultImpl} from "../../../src/implementation/ConcreteStandardVaultImpl.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";
import {VaultProxy} from "../../../src/factory/VaultProxy.sol";

contract InitializationUnitTest is Test {
    ConcreteStandardVaultImpl public concreteStandardVaultImpl;
    address public owner = makeAddr("owner");
    address public factoryOwner = makeAddr("factoryOwner");
    address public allocateModule = makeAddr("allocateModule");
    address public asset = makeAddr("asset");
    address public initialVaultManager = makeAddr("initialVaultManager");
    string public name = "name";
    string public symbol = "symbol";

    function setUp() public {
        concreteStandardVaultImpl = new ConcreteStandardVaultImpl(address(this));
    }

    function testInitialize() public {
        bytes memory data = abi.encode(allocateModule, asset, initialVaultManager, name, symbol);
        VaultProxy vaultProxy = new VaultProxy(
            address(concreteStandardVaultImpl),
            abi.encodeWithSignature("initialize(uint64,address,bytes)", 1, owner, data)
        );

        IConcreteStandardVaultImpl newConcreteStandardVaultImpl = IConcreteStandardVaultImpl(address(vaultProxy));
        address allocateModuleAddr = newConcreteStandardVaultImpl.allocateModule();
        assertEq(allocateModuleAddr, allocateModule, "allocateModuleAddr");

        address assetAddr = newConcreteStandardVaultImpl.asset();
        assertEq(assetAddr, asset, "assetAddr");

        (uint256 maxDepositAmount, uint256 minDepositAmount) = newConcreteStandardVaultImpl.getDepositLimits();
        (uint256 maxWithdrawAmount, uint256 minWithdrawAmount) = newConcreteStandardVaultImpl.getWithdrawLimits();

        assertEq(maxDepositAmount, type(uint256).max);
        assertEq(minDepositAmount, 0);
        assertEq(maxWithdrawAmount, type(uint256).max);
        assertEq(minWithdrawAmount, 0);
    }

    function testInitializeRevertsIfInvalidAllocateModule() public {
        bytes memory data = abi.encode(address(0), asset, initialVaultManager, name, symbol);
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidAllocateModule.selector));
        new VaultProxy(
            address(concreteStandardVaultImpl),
            abi.encodeWithSignature("initialize(uint64,address,bytes)", 1, owner, data)
        );
    }

    function testInitializeRevertsIfInvalidAsset() public {
        bytes memory data = abi.encode(allocateModule, address(0), initialVaultManager, name, symbol);
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidAsset.selector));
        new VaultProxy(
            address(concreteStandardVaultImpl),
            abi.encodeWithSignature("initialize(uint64,address,bytes)", 1, owner, data)
        );
    }

    function testInitializeRevertsIfInvalidInitialVaultManager() public {
        bytes memory data = abi.encode(allocateModule, asset, address(0), name, symbol);
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidInitialVaultManager.selector));
        new VaultProxy(
            address(concreteStandardVaultImpl),
            abi.encodeWithSignature("initialize(uint64,address,bytes)", 1, owner, data)
        );
    }

    function testInitializeRevertsIfInvalidName() public {
        bytes memory data = abi.encode(allocateModule, asset, initialVaultManager, "", symbol);
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidName.selector));
        new VaultProxy(
            address(concreteStandardVaultImpl),
            abi.encodeWithSignature("initialize(uint64,address,bytes)", 1, owner, data)
        );
    }

    function testInitializeRevertsIfInvalidSymbol() public {
        bytes memory data = abi.encode(allocateModule, asset, initialVaultManager, name, "");
        vm.expectRevert(abi.encodeWithSelector(IConcreteStandardVaultImpl.InvalidSymbol.selector));
        new VaultProxy(
            address(concreteStandardVaultImpl),
            abi.encodeWithSignature("initialize(uint64,address,bytes)", 1, owner, data)
        );
    }
}
