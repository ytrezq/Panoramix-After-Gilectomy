// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {ILossPolicy} from "@gearbox-protocol/core-v3/contracts/interfaces/base/ILossPolicy.sol";

contract MockLossPolicy is ILossPolicy {
    uint256 public constant version = 3_10;
    bytes32 public constant contractType = "LOSS_POLICY::MOCK";

    AccessMode public override accessMode = AccessMode.Permissionless;
    bool public override checksEnabled = true;

    constructor(address pool, address addressProvider) {}

    function serialize() external pure override returns (bytes memory) {}

    function isLiquidatableWithLoss(address, address, Params calldata) external view override returns (bool) {
        return !checksEnabled && accessMode == AccessMode.Permissionless;
    }

    function setAccessMode(AccessMode mode) external override {
        accessMode = mode;
    }

    function setChecksEnabled(bool enabled) external override {
        checksEnabled = enabled;
    }
}
