// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IDepositWithdraw {
    enum BalanceCheckFlag {
        Both,
        From,
        To,
        None
    }
    function depositWeiIntoDefaultAccount(uint256 _marketId, uint256 _amountWei) external;
    function withdrawWeiFromDefaultAccount(uint256 _marketId, uint256 _amountWei, BalanceCheckFlag _balanceCheckFlag) external;
}