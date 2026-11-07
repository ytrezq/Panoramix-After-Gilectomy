// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EthereumScript} from 'aave-helpers/ScriptUtils.sol';
import {AaveMisc} from 'aave-address-book/AaveMisc.sol';
import {AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {StakedAaveV3} from '../src/contracts/StakedAaveV3.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

contract DeployStkAaveToken is EthereumScript {
  uint256 public constant UNSTAKE_WINDOW = 172800; // 2 days
  uint128 public constant DISTRIBUTION_DURATION = 3155692600; // 100 years
  address public constant EMISSION_MANAGER =
    GovernanceV3Ethereum.EXECUTOR_LVL_1; // SHORT EXECUTOR

  function run() external broadcast {
    new StakedAaveV3(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING),
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING),
      UNSTAKE_WINDOW,
      AaveMisc.ECOSYSTEM_RESERVE,
      EMISSION_MANAGER,
      DISTRIBUTION_DURATION
    );
  }
}
