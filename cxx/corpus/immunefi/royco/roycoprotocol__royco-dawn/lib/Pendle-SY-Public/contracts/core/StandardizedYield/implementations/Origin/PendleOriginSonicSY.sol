// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../PendleERC4626UpgSYV2.sol";
import "../../../../interfaces/Origin/IOETHVault.sol";

contract PendleOriginSonicSY is PendleERC4626UpgSYV2 {
    address public constant WOS = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;
    address public constant WS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address public constant OS_VAULT = 0xa3c0eCA00D2B76b4d1F170b0AB3FdeA16C180186;

    constructor() PendleERC4626UpgSYV2(WOS) {
        assert(block.chainid == 146);
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY Wrapped OS", "SY-wOS");
        _safeApproveInf(asset, yieldToken);
        _safeApproveInf(WS, OS_VAULT);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == yieldToken) {
            return amountDeposited;
        } else {
            if (tokenIn == WS) {
                IOETHVault(OS_VAULT).mint(WS, amountDeposited, 0);
            }
            return IERC4626(yieldToken).deposit(amountDeposited, address(this));
        }
    }

    function getTokensIn() public view override returns (address[] memory res) {
        res = new address[](3);
        res[0] = WS;
        res[1] = asset;
        res[2] = yieldToken;
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldToken || token == asset || token == WS;
    }
}
