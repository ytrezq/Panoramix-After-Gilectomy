// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IGMXViewer {
    function getWithdrawalAmountOut(address market, uint256 amount, bool stalenessCheck) external view returns (uint256);
    function getDepositAmountOut(address market, uint256 amount, bool stalenessCheck) external view returns (uint256);
}