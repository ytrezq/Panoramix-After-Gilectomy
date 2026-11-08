// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./Base.s.sol";

import { BridgeableTokenP } from "contracts/tokens/BridgeableTokenP/BridgeableTokenP.sol";

contract TransferOwnership is BaseScript {
    BridgeableTokenP bridgeableTokenP =
        BridgeableTokenP(0x72b089bD4386E5B4eB1485a6c913c14F75a24657);

    function run() public broadcast {
        bridgeableTokenP.transferOwnership(address(accessManager));
    }
}
