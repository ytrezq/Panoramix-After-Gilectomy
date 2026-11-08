// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { ForceTransferBera } from "../logic/ForceTransferBera.sol";

contract TransferBeraScript is BaseScript, ForceTransferBera {
    /// @notice Force transfer BERA to a receiver.
    /// @dev sender must have enough balance to transfer.
    function run(address to, uint256 amount) public virtual broadcast {
        console2.log("Reciver address: ", to);

        forceSafeTransferBERATo(to, amount);
        console2.log("Sent %d BERA to %s", amount, to);
    }
}
