// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract AnvilHelper is Script {
    using LibString for address;
    using LibString for uint256;
    using LibString for bytes;

    function _setBalance(address account, uint256 balance) internal {
        vm.rpc("anvil_setBalance", string.concat("[\"", account.toHexString(), "\", \"", balance.toHexString(), "\"]"));
    }

    function _autoImpersonate(bool autoImpersonate) internal {
        vm.rpc("anvil_autoImpersonateAccount", string.concat("[", vm.toString(autoImpersonate), "]"));
    }

    function _impersonate(address account) internal {
        vm.rpc("anvil_impersonateAccount", string.concat("[\"", account.toHexString(), "\"]"));
    }

    function _stopImpersonate(address account) internal {
        vm.rpc("anvil_stopImpersonatingAccount", string.concat("[\"", account.toHexString(), "\"]"));
    }

    function _setCode(address account, bytes memory code) internal {
        vm.rpc("anvil_setCode", string.concat("[\"", account.toHexString(), "\", \"", code.toHexString(), "\"]"));
    }

    function _replaceBytecode(address account, bytes memory newBytecode) internal {
        if (vm.isContext(VmSafe.ForgeContext.ScriptGroup)) {
            _setCode(account, newBytecode);
        }
        vm.etch(account, newBytecode);
    }
}
