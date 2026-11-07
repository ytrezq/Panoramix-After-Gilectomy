// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
interface IIdleCDOStrategy {
  function getApr() external view returns(uint256);
}