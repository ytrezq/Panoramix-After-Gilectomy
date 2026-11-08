// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../SYBaseWithRewardsUpg.sol";
import "../../../../interfaces/Infrared/IInfraredBGTVault.sol";

contract PendleInfraredBGTSY is SYBaseWithRewardsUpg {
    address public constant VAULT = 0x75F3Be06b02E235f6d0E7EF2D462b29739168301;
    address public constant IBGT = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;
    address public constant HONEY = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address public constant BERA = 0x6969696969696969696969696969696969696969;

    constructor() SYBaseUpg(IBGT) {}

    function initialize() external initializer {
        __SYBaseUpg_init("SY Staked Infrared BGT", "SY-iBGT");
        _safeApproveInf(IBGT, VAULT);
    }

    function _deposit(
        address /*tokenIn*/,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        IInfraredBGTVault(VAULT).stake(amountDeposited);
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        IInfraredBGTVault(VAULT).withdraw(amountSharesToRedeem);
        _transferOut(IBGT, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public view virtual override returns (uint256) {
        return PMath.ONE;
    }

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
        return ArrayLib.create(IBGT);
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        return ArrayLib.create(IBGT);
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == IBGT;
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return token == IBGT;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, IBGT, 18);
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    function _getRewardTokens() internal pure override returns (address[] memory res) {
        return ArrayLib.create(HONEY, BERA);
    }

    function _redeemExternalReward() internal override {
        IInfraredBGTVault(VAULT).getRewardForUser(address(this));
    }
}
