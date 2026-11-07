// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;


interface IIntegration {
    function name() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
}
