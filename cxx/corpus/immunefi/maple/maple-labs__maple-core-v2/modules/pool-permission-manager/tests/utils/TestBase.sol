// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { console2 as console, Test } from "../../modules/forge-std/src/Test.sol";

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { MaplePoolPermissionManagerInitializer } from "../../contracts/proxy/MaplePoolPermissionManagerInitializer.sol";

import { MaplePoolPermissionManager } from "../../contracts/MaplePoolPermissionManager.sol";

import { GlobalsMock } from "../utils/Mocks.sol";
import { TestBase }    from "../utils/TestBase.sol";

// TODO: Add event assertions to all tests.
contract TestBase is Test {

    bytes internal constant assertionError      = abi.encodeWithSignature("Panic(uint256)", 0x01);
    bytes internal constant arithmeticError     = abi.encodeWithSignature("Panic(uint256)", 0x11);
    bytes internal constant divisionError       = abi.encodeWithSignature("Panic(uint256)", 0x12);
    bytes internal constant enumConversionError = abi.encodeWithSignature("Panic(uint256)", 0x21);
    bytes internal constant encodeStorageError  = abi.encodeWithSignature("Panic(uint256)", 0x22);
    bytes internal constant popError            = abi.encodeWithSignature("Panic(uint256)", 0x31);
    bytes internal constant indexOOBError       = abi.encodeWithSignature("Panic(uint256)", 0x32);
    bytes internal constant memOverflowError    = abi.encodeWithSignature("Panic(uint256)", 0x41);
    bytes internal constant zeroVarError        = abi.encodeWithSignature("Panic(uint256)", 0x51);

    address governor         = makeAddr("governor");
    address lender           = makeAddr("lender");
    address operationalAdmin = makeAddr("operationalAdmin");
    address permissionAdmin  = makeAddr("permissionAdmin");
    address poolDelegate     = makeAddr("poolDelegate");
    address poolManager      = makeAddr("poolManager");

    address implementation = address(new MaplePoolPermissionManager());
    address initializer    = address(new MaplePoolPermissionManagerInitializer());

    bytes32 functionId = "P:deposit";

    address[] lenders;
    uint256[] bitmaps;
    bool   [] booleans;
    bytes32[] functionIds;

    GlobalsMock                globals;
    MaplePoolPermissionManager ppm;

    function setUp() public virtual {
        globals = new GlobalsMock();

        globals.__setGovernor(governor);
        globals.__setOperationalAdmin(operationalAdmin);
        globals.__setOwnedPoolManager(poolDelegate, poolManager, true);

        ppm = MaplePoolPermissionManager(address(new NonTransparentProxy(governor, address(initializer))));

        vm.startPrank(governor);
        MaplePoolPermissionManagerInitializer(address(ppm)).initialize(implementation, address(globals));
        ppm.setPermissionAdmin(permissionAdmin, true);
        vm.stopPrank();
    }

    function generateBitmap(uint8[2] memory indices_) internal pure returns (uint256 bitmap_) {
        for (uint8 i = 0; i < indices_.length; i++) {
            bitmap_ |= (1 << indices_[i]);
        }
    }

    function generateBitmap(uint8[3] memory indices_) internal pure returns (uint256 bitmap_) {
        for (uint8 i = 0; i < indices_.length; i++) {
            bitmap_ |= (1 << indices_[i]);
        }
    }

}
