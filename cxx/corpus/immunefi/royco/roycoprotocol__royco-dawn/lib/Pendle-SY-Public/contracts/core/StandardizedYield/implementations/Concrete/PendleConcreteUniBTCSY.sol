// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./PendleConcreteVaultSY.sol";
import "../../../../interfaces/Bedrock/IBedrockUniBTCVault.sol";

contract PendleConcreteUniBTCSY is PendleConcreteVaultSY {
    address public constant VAULT = 0x047D41F2544B7F63A8e991aF2068a363d210d6Da;
    address public constant UNIBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant FBTC = 0xC96dE26018A54D51c097160568752c4E3BD6C364;
    address public constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    constructor() PendleConcreteVaultSY(0xB1Cdf3C96000330f018b7d7dF5bEe5E7F9E13b62) {}

    function initialize(string memory _name, string memory _symbol) external virtual override initializer {
        __SYBaseUpg_init(_name, _symbol);
        _safeApproveInf(asset, yieldToken);
        _safeApproveInf(WBTC, VAULT);
        _safeApproveInf(FBTC, VAULT);
        _safeApproveInf(CBBTC, VAULT);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn != yieldToken && tokenIn != asset) {
            IBedrockUniBTCVault(VAULT).mint(tokenIn, amountDeposited);
            (tokenIn, amountDeposited) = (asset, _selfBalance(asset));
        }
        return super._deposit(tokenIn, amountDeposited); /// (WBTC & FBTC both have 8 decimals)
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == WBTC || token == FBTC || token == CBBTC || token == UNIBTC || token == yieldToken;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(WBTC, FBTC, CBBTC, UNIBTC, yieldToken);
    }
}
