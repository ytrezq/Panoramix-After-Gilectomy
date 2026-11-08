// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.26;

interface ILinearPoolRebalancer {
    function rebalance(address recipient) external;
    function rebalanceWithExtraMain(address recipient, uint extraMain) external;
}