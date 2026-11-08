// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {CreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditConfiguratorV3.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

contract MockCreditConfiguratorPatch is CreditConfiguratorV3, Test {
    constructor(address _creditManager) CreditConfiguratorV3(_creditManager) {
        vm.mockCall(address(this), abi.encodeCall(IVersion.version, ()), abi.encode(311));
    }
}
