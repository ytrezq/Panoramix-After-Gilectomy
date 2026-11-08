// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IUpgradeSource {

  function shouldUpgrade() external view returns (bool, address);

  function finalizeUpgrade() external;
}
