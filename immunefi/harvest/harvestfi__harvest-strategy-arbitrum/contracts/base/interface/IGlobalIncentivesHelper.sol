//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IGlobalIncentivesHelper {
  function notifyPools(address[] calldata tokens, uint256[] calldata totals, uint256 timestamp) external;
}