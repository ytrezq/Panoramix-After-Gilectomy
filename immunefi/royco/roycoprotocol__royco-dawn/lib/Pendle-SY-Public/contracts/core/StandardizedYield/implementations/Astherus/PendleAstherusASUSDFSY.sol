// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/Astherus/IAstherusEarn.sol";

contract PendleAstherusASUSDFSY is SYBaseUpg {
    address public constant BINANCE_USD = 0x55d398326f99059fF775485246999027B3197955;
    address public constant USDF_EARN = 0xC271fc70dD9E678ac1AB632f797894fe4BE2C345;

    address public constant ASUSDF = 0x917AF46B3C3c6e1Bb7286B9F59637Fb7C65851Fb;
    address public constant USDF = 0x5A110fC00474038f6c02E89C707D638602EA44B5;
    address public constant EARN = 0xdB57a53C428a9faFcbFefFB6dd80d0f427543695;

    constructor() SYBaseUpg(ASUSDF) {}

    function initialize() external initializer {
        __SYBaseUpg_init("SY Astherus asUSDF", "SY-asUSDF");
        _safeApproveInf(USDF, EARN);
        _safeApproveInf(BINANCE_USD, USDF_EARN);
    }

    function approveUsdfEarn() external onlyOwner {
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
            IAstherusEarn(USDF_EARN).deposit(amountDeposited);
            (tokenIn, amountDeposited) = (USDF, _selfBalance(USDF));
        }
        if (tokenIn != ASUSDF) {
            uint256 preBalance = _selfBalance(ASUSDF);
            IAstherusEarn(EARN).deposit(amountDeposited);
            amountDeposited = _selfBalance(ASUSDF) - preBalance;
        }
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        _transferOut(ASUSDF, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return IAstherusEarn(EARN).exchangePrice();
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == ASUSDF) return amountTokenToDeposit;
        return PMath.divDown(amountTokenToDeposit, IAstherusEarn(EARN).exchangePrice());
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public pure override returns (address[] memory res) {
        return ArrayLib.create(USDF, ASUSDF, BINANCE_USD);
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        return ArrayLib.create(ASUSDF);
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == USDF || token == ASUSDF || token == BINANCE_USD;
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return token == ASUSDF;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, USDF, IERC20Metadata(USDF).decimals());
    }
}
