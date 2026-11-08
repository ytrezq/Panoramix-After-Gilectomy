// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./PendleConcreteVaultSY.sol";
import "../Solv/PendleSolvHelper.sol";

contract PendleConcreteSolvBTCBBNSY is PendleConcreteVaultSY {
    using ArrayLib for address[];

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant SOLV_BTC = 0x7A56E1C57C7475CCf742a1832B028F0456652F97;
    address public constant SOLV_BBN_BTC = 0xd9D920AA40f578ab794426F5C90F6C731D159DEf;

    constructor() PendleConcreteVaultSY(0x5a35b8817cB92dCd7196B243351f018C4982C010) {}

    address[] internal FULL_PATH;
    function initialize(string memory _name, string memory _symbol) external override initializer {
        __SYBaseUpg_init(_name, _symbol);
        _safeApproveInf(WBTC, PendleSolvHelper.SOLV_BTC_ROUTER);
        _safeApproveInf(SOLV_BTC, PendleSolvHelper.SOLV_BTCBBN_ROUTER);
        _safeApproveInf(asset, yieldToken);
        FULL_PATH = ArrayLib.create(WBTC, SOLV_BTC, SOLV_BBN_BTC);
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual override returns (uint256) {
        if (tokenIn != yieldToken && tokenIn != asset) {
            (tokenIn, amountDeposited) = (asset, PendleSolvHelper._mintBTCBBN(tokenIn, amountDeposited));
        }
        return super._deposit(tokenIn, amountDeposited);
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn != yieldToken && tokenIn != asset) {
            (tokenIn, amountTokenToDeposit) = (
                asset,
                PendleSolvHelper._previewMintBTCBBN(tokenIn, amountTokenToDeposit)
            );
        }
        return super._previewDeposit(tokenIn, amountTokenToDeposit);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == WBTC || token == SOLV_BTC || token == SOLV_BBN_BTC || token == yieldToken;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return FULL_PATH.append(yieldToken);
    }
}
