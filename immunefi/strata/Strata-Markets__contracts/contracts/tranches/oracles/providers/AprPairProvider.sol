// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStrategyAprPairProvider, IAprProvider } from "../../interfaces/IAprPairFeed.sol";
import { IAccessControlManager } from "../../../governance/interfaces/IAccessControlManager.sol";

/**
 * @title Common AprPairProvider with configurable single providers for Target (Benchmark) and Base APR
 */
contract AprPairProvider is IStrategyAprPairProvider {

    IAprProvider immutable public target;
    IAprProvider immutable public base;

    constructor(
        IAprProvider _target,
        IAprProvider _base
    ) {
        target = _target;
        base = _base;
    }

    function getAprPair()
        external
        view
        returns (int64 aprTarget, int64 aprBase, uint64 timestamp)
    {
        timestamp = uint64(block.timestamp);
        (aprTarget, ) = target.getApr();
        (aprBase, ) = base.getApr();
    }
}
