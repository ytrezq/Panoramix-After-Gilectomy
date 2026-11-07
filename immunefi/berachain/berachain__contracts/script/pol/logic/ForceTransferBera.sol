// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";

abstract contract ForceTransferBera {
    /// @notice Force transfer BERA to BGT contract using SELFDESTRUCT opcode.
    function forceSafeTransferBERATo(address to, uint256 amount) public {
        require(msg.sender.balance >= amount, "Sender balance is less than the amount to transfer");
        // The BGT contract doesn't have `fallback` or `receive` functions, so we need to use `forceSafeTransferETH` to
        // send BERA to it.
        // SafeTransferLib.forceSafeTransferETH(address(bgt), amount);
        assembly ("memory-safe") {
            mstore(0x00, to) // Store the address in scratch space.
            mstore8(0x0b, 0x73) // Opcode `PUSH20`.
            mstore8(0x20, 0xff) // Opcode `SELFDESTRUCT`.
            if iszero(create(amount, 0x0b, 0x16)) { revert(0, 0) }
        }
        console2.log("Sent %d BERA to %s", amount, to);
    }
}
