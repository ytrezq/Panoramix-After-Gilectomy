// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Bytecode} from "../contracts/interfaces/Types.sol";

import {AttachScriptBase} from "../contracts/test/suite/AttachScriptBase.sol";

abstract contract UploadBytecode is AttachScriptBase {
    address public author;

    function setUp() public virtual {
        _attachCore();

        address[] memory wallets = vm.getWallets();
        if (wallets.length == 0) revert("No unlocked wallets found");
        author = wallets[0];
    }

    function run() public virtual {
        vm.startBroadcast(author);
        Bytecode[] memory bytecodes = _getContracts();
        for (uint256 i; i < bytecodes.length; ++i) {
            _signBytecode(author, bytecodes[i]);
            bytecodeRepository.uploadBytecode(bytecodes[i]);
        }
        vm.stopBroadcast();
    }

    function _getContracts() internal view virtual returns (Bytecode[] memory bytecodes);
}
