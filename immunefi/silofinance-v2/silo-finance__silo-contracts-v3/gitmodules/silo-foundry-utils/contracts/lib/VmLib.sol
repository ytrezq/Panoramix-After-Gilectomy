// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {Vm, VmSafe} from "forge-std/Vm.sol";

library VmLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant _VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    function vm() internal pure returns (Vm) {
        return Vm(_VM_ADDRESS);
    }

    function vmSafe() internal pure returns (VmSafe) {
        return VmSafe(_VM_ADDRESS);
    }
}
