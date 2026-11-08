// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./PendleSolvSYBaseV2.sol";

contract PendleSolvBeraBTCSY is PendleSolvSYBaseV2 {
    address public constant SOLV_BTC_ROUTER_V2 = 0x3d93B9e8F0886358570646dAd9421564C5fE6334;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant SOLV_BTC = 0x7A56E1C57C7475CCf742a1832B028F0456652F97;
    address public constant SOLV_BBN_BTC = 0xd9D920AA40f578ab794426F5C90F6C731D159DEf;
    address public constant SOLV_BERA_BTC = 0xE7C253EAD50976Caf7b0C2cbca569146A7741B50;

    address[] internal FULL_PATH;

    constructor() PendleSolvSYBaseV2(SOLV_BTC_ROUTER_V2, SOLV_BERA_BTC) {}

    function initialize(string memory _name, string memory _symbol) external initializer {
        __SYBaseUpg_init(_name, _symbol);
        _safeApproveInf(WBTC, SOLV_BTC_ROUTER_V2);
        _safeApproveInf(SOLV_BTC, SOLV_BTC_ROUTER_V2);
        _safeApproveInf(SOLV_BBN_BTC, SOLV_BTC_ROUTER_V2);
        FULL_PATH = ArrayLib.create(WBTC, SOLV_BTC, SOLV_BBN_BTC, SOLV_BERA_BTC);
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 /*amountSharesOut*/) {
        for (uint256 i = 0; i + 1 < FULL_PATH.length; ++i) {
            if (tokenIn == FULL_PATH[i]) {
                address nxtToken = FULL_PATH[i + 1];
                bytes32 poolId = ISolvRouterV2(solvRouterV2).poolIds(nxtToken, tokenIn);
                (tokenIn, amountTokenToDeposit) = (nxtToken, _previewSolvConvert(poolId, amountTokenToDeposit));
            }
        }
        assert(tokenIn == SOLV_BERA_BTC);
        return amountTokenToDeposit;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return FULL_PATH;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == WBTC || token == SOLV_BERA_BTC || token == SOLV_BTC || token == SOLV_BBN_BTC;
    }
}
