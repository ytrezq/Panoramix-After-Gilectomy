// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {PriceOracleV3} from "@gearbox-protocol/core-v3/contracts/core/PriceOracleV3.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

contract MockPriceOraclePatch is PriceOracleV3, Test {
    constructor(address _acl) PriceOracleV3(_acl) {
        vm.mockCall(address(this), abi.encodeCall(IVersion.version, ()), abi.encode(311));
    }
}
