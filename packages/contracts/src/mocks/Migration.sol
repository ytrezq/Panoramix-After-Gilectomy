// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/**
 * @title Migration
 *
 * @dev This file allows importing contracts to obtain compiler artifacts for testing purposes.
 *
 * After a contract is imported here and the project is compiled, an associated artifact will be
 * generated inside artifacts/@aragon/{version-name}/*,
 * and TypeChain typings will be generated inside typechain/osx-version/{version-name}/*
 * for type-safe interactions with the contract in our tests.
 */

/* solhint-disable no-unused-import */

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginRepo} from "@aragon/osx-v1.3.0/framework/plugin/repo/PluginRepo.sol";
import {ProxyFactory} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyFactory.sol";

/* solhint-enable no-unused-import */
