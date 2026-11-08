// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

// 🧩 MODULES
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {stdError} from "forge-std/StdError.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {stdMath} from "forge-std/StdMath.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

// 📦 BOILERPLATE
import {TestBase} from "forge-std/Base.sol";

import {AddressesCollection} from "./addresses/AddressesCollection.sol";

contract IntegrationTest is TestBase, StdAssertions, StdCheats, StdInvariant, StdUtils, AddressesCollection {}
