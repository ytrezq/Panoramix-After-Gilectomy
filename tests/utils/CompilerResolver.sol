// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

// This file is needed to force a compile of MapleGlobals, so the artifact is available to deploy using the foundry cheatcode.
import { MockERC20 }    from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";
import { MapleGlobals } from "../../modules/globals/contracts/MapleGlobals.sol";
import { Migrator }     from "../../modules/migrator/contracts/Migrator.sol";
