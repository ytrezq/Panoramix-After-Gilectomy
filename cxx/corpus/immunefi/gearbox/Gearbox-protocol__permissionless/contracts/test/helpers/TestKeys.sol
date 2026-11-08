// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

contract TestKeys is Test {
    using LibString for uint256;

    VmSafe.Wallet internal _signer1;
    VmSafe.Wallet internal _signer2;
    VmSafe.Wallet internal _dao;
    VmSafe.Wallet internal _instanceOwner;
    VmSafe.Wallet internal _auditor;
    VmSafe.Wallet internal _bytecodeAuthor;

    uint8 public threshold = 2;

    constructor() {
        _signer1 = vm.createWallet(_generatePrivateKey("SIGNER_1"));
        _signer2 = vm.createWallet(_generatePrivateKey("SIGNER_2"));
        uint256 daoPrivateKey = _generatePrivateKey("DAO");
        vm.rememberKey(daoPrivateKey);
        _dao = vm.createWallet(daoPrivateKey);
        _instanceOwner = vm.createWallet(_generatePrivateKey("INSTANCE_OWNER"));
        _auditor = vm.createWallet(_generatePrivateKey("AUDITOR"));
        _bytecodeAuthor = vm.createWallet(_generatePrivateKey("BYTECODE_AUTHOR"));
    }

    function initialSigners() external view returns (VmSafe.Wallet[] memory result) {
        result = new VmSafe.Wallet[](2);
        result[0] = _signer1;
        result[1] = _signer2;
    }

    function _generatePrivateKey(string memory salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(salt)));
    }

    function signer1() external view returns (VmSafe.Wallet memory) {
        return _signer1;
    }

    function signer2() external view returns (VmSafe.Wallet memory) {
        return _signer2;
    }

    function dao() external view returns (VmSafe.Wallet memory) {
        return _dao;
    }

    function instanceOwner() external view returns (VmSafe.Wallet memory) {
        return _instanceOwner;
    }

    function auditor() external view returns (VmSafe.Wallet memory) {
        return _auditor;
    }

    function bytecodeAuthor() external view returns (VmSafe.Wallet memory) {
        return _bytecodeAuthor;
    }

    function printKeys() external view {
        console.log("Cross chain multisig setup:");
        console.log("Signer 1:", _signer1.addr, "Key:", uint256(_signer1.privateKey).toHexString());
        console.log("Signer 2:", _signer2.addr, "Key:", uint256(_signer2.privateKey).toHexString());
        console.log("DAO:", _dao.addr, "Key:", uint256(_dao.privateKey).toHexString());
        console.log("Instance Owner:", _instanceOwner.addr, "Key:", uint256(_instanceOwner.privateKey).toHexString());
        console.log("Auditor:", _auditor.addr, "Key:", uint256(_auditor.privateKey).toHexString());
    }
}
