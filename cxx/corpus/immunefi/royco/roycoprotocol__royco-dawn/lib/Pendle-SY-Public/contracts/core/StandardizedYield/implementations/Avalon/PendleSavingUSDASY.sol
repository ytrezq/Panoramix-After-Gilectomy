// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/Avalon/IAvalonSaving.sol";

contract PendleSavingUSDASY is SYBaseUpg {
    address public constant SAVING = 0x01e3cc8E17755989ad2CAFE78A822354Eb5DdFA6;
    address public constant SUSDA = 0x2B66AAdE1e9C062FF411bd47C44E0Ad696d43BD9;
    address public constant USDA = 0x8A60E489004Ca22d775C5F2c657598278d17D9c2;

    constructor() SYBaseUpg(SUSDA) {}

    function initialize() external initializer {
        __SYBaseUpg_init("SY USDa saving token", "SY-sUSDa");
        _safeApproveInf(USDA, SAVING);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn != SUSDA) {
            uint256 preBalance = _selfBalance(SUSDA);
            IAvalonSaving(SAVING).mint(amountDeposited);
            amountDeposited = _selfBalance(SUSDA) - preBalance;
        }
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        _transferOut(SUSDA, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        uint256 totalUnderlying = IAvalonSaving(SAVING).getTotalUnderlying();
        uint256 totalSUSDA = IAvalonSaving(SAVING).totalsUSDaLockedAmount();
        return PMath.divDown(totalUnderlying, totalSUSDA);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == SUSDA) return amountTokenToDeposit;
        return IAvalonSaving(SAVING).getSharesByAmount(amountTokenToDeposit);
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public pure override returns (address[] memory res) {
        return ArrayLib.create(USDA, SUSDA);
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        return ArrayLib.create(SUSDA);
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == USDA || token == SUSDA;
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return token == SUSDA;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, USDA, IERC20Metadata(USDA).decimals());
    }
}
