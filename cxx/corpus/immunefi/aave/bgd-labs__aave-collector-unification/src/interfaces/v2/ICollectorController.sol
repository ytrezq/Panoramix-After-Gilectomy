// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import {IERC20} from '@aave/core-v2/contracts/dependencies/openzeppelin/contracts/IERC20.sol';

interface ICollectorController {
  function transfer(
    address collector,
    IERC20 token,
    address recipient,
    uint256 amount
  ) external;
}
