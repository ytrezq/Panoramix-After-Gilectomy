// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IDepositWithdraw {
    enum BalanceCheckFlag {
        Both,
        From,
        To,
        None
    }
    function DEFAULT_ACCOUNT_NUMBER() external view returns (uint256);
    function depositWei(uint256 _isolationModeMarketId, uint256 _toAccountNumber, uint256 _marketId, uint256 _amountWei, uint8 _eventFlag) external;
    function withdrawWei(uint256 _isolationModeMarketId, uint256 _fromAccountNumber, uint256 _marketId, uint256 _amountWei, uint8 _balanceCheckFlag) external;
}