//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IUpgradeableStrategy {
  function scheduleUpgrade(address impl) external;
  function upgrade() external;
}
