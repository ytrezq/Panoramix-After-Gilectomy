// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../PendleERC4626UpgSYV2.sol";
import "../../../../interfaces/Angles/IAnglesVault.sol";

contract PendleWanSSY is PendleERC4626UpgSYV2 {
    address public constant ANGLES_VAULT = 0xe5203Be1643465b3c0De28fd2154843497Ef4269;

    constructor() PendleERC4626UpgSYV2(0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70) {}

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            IAnglesVault(ANGLES_VAULT).deposit{value: amountDeposited}();
            tokenIn = asset;
        }
        return super._deposit(tokenIn, amountDeposited);
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, asset, yieldToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == asset || token == yieldToken;
    }

    // @note: Preview functions check token == yieldToken to differentiate methods, so we dont
    // have to override them with other logics
}
