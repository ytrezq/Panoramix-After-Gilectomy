// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStrategyAprPairProvider} from "../../interfaces/IAprPairFeed.sol";
import {IAccessControlManager} from "../../../governance/interfaces/IAccessControlManager.sol";
import {ChainlinkAprProviderLib} from "../../oracles/providers/ChainlinkAprProviderLib.sol";
import {IRoundDataOracle} from "../../oracles/interfaces/IRoundDataOracle.sol";

/**
 * @title AprPairProvider with Static as Target APR and Oracle as Base APR
 * @notice Constant target APR and base APR from Oracle price increase for the latest Round
 */

contract ConstantOracleAprPairProvider is IStrategyAprPairProvider {
    IRoundDataOracle immutable public oracle;

    constructor(IRoundDataOracle _oracle) {
        oracle = _oracle;
    }

    function getAprPair()
        external
        view
        returns (int64 aprTarget, int64 aprBase, uint64 timestamp)
    {
        timestamp = uint64(block.timestamp);
        aprTarget = 0;
        aprBase = ChainlinkAprProviderLib.getApr(oracle);
    }
}
