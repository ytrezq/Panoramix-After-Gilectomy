// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";

import "../../../../interfaces/Astherus/IAstherusEarn.sol";

contract PendleAstherusUSDFSY is SYBaseUpg {
    address public constant BINANCE_USD = 0x55d398326f99059fF775485246999027B3197955;
    address public constant USDF_EARN = 0xC271fc70dD9E678ac1AB632f797894fe4BE2C345;
    address public constant USDF = 0x5A110fC00474038f6c02E89C707D638602EA44B5;

    constructor() SYBaseUpg(USDF) {}

    function initialize() external initializer {
        __SYBaseUpg_init("SY Astherus USDF", "SY-USDF");
        _safeApproveInf(BINANCE_USD, USDF_EARN);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == BINANCE_USD) {
            uint256 preBalance = _selfBalance(USDF);
            IAstherusEarn(USDF_EARN).deposit(amountDeposited);
            (tokenIn, amountDeposited) = (USDF, _selfBalance(USDF) - preBalance);
        }
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        _transferOut(USDF, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return PMath.ONE;
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address /*tokenIn*/,
        uint256 amountTokenToDeposit
    ) internal pure override returns (uint256 /*amountSharesOut*/) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public pure override returns (address[] memory res) {
        return ArrayLib.create(USDF, BINANCE_USD);
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        return ArrayLib.create(USDF);
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == USDF || token == BINANCE_USD;
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return token == USDF;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, USDF, IERC20Metadata(USDF).decimals());
    }
}
