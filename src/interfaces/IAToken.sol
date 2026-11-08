// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';

interface IAToken is IERC20 {
  function RESERVE_TREASURY_ADDRESS() external view returns (address);
}
