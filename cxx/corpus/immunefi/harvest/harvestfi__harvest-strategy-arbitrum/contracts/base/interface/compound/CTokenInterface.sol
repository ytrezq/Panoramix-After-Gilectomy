// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

abstract contract CTokenInterface {
    address public underlying;

    function balanceOfUnderlying(address owner) external virtual returns (uint);

    function borrowBalanceCurrent(
        address account
    ) external virtual returns (uint);

    function exchangeRateCurrent() external virtual returns (uint);

    function getCash() external view virtual returns (uint);

    function totalBorrows() external view virtual returns (uint);

    function mint(uint mintAmount) external virtual returns (uint);
    function mint() external payable virtual;

    function redeemUnderlying(uint redeemAmount) external virtual returns (uint);
    function redeem(uint redeemTokens) external virtual returns (uint);

    function borrow(uint borrowAmount) external virtual returns (uint);

    function repayBorrow(uint repayAmount) external virtual returns (uint);
    function repayBorrow() external payable virtual;
}