// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "../PendleERC4626UpgSYV2.sol";

contract PendleConcreteVaultSY is PendleERC4626UpgSYV2 {
    error ConcreteInsufficientInstantAmountOut();

    constructor(address _concreteVault) PendleERC4626UpgSYV2(_concreteVault) {}

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        if (tokenOut == yieldToken) {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(yieldToken, receiver, amountTokenOut);
        } else {
            uint256 preBalance = IERC20(tokenOut).balanceOf(receiver);
            amountTokenOut = IERC4626(yieldToken).redeem(amountSharesToRedeem, receiver, address(this));
            uint256 instantAmountOut = IERC20(tokenOut).balanceOf(receiver) - preBalance;

            if (instantAmountOut < amountTokenOut) {
                revert ConcreteInsufficientInstantAmountOut();
            }
        }
    }
}
