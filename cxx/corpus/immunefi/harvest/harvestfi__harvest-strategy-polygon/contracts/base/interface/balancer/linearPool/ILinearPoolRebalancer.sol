// SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

interface ILinearPoolRebalancer {
    function rebalance(address recipient) external;
    function rebalanceWithExtraMain(address recipient, uint extraMain) external;
}