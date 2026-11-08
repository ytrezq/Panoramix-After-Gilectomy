//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IDistributor {
    function toggleOperator(address user, address operator) external;
}