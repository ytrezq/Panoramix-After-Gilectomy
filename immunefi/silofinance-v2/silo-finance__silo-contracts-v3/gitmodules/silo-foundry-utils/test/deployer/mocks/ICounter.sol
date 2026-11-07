// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

interface ICounter {
    function setSomeNumber() external;
    function increment() external;

    function multiplier() external view returns (uint256);
    function someNumber() external view returns (uint256);
}
