// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { console2 as console, Test } from "../../modules/forge-std/src/Test.sol";

// TODO: Check if this can be removed and `Test` inherited directly.
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

    function deployGlobals() internal returns (address globals_) {
        globals_ = deployCode("MapleGlobals.sol");
    }

    function deployMockERC20() internal returns (address mockERC20_) {
        mockERC20_ = deployCode("MockERC20.sol", abi.encode("MOCK", "MOCK", 18));
    }

}

