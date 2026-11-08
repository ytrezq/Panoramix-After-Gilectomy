//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IDistributor {
    function toggleOperator(address user, address operator) external;
}