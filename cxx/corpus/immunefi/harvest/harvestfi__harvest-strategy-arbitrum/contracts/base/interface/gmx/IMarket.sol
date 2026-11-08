// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IMarket {
    function dataStore() external view returns (address);
    function roleStore() external view returns (address);
}