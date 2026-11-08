// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IHandler {
    struct SetPricesParams {
        address[] tokens;
        address[] providers;
        bytes[] data;
    }
    function executeDeposit(bytes32 key, SetPricesParams calldata oracleParams) external;
    function executeWithdrawal(bytes32 key, SetPricesParams calldata oracleParams) external;
}