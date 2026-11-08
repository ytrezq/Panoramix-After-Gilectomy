// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/IERC4626.sol";
import "../../../../interfaces/Beets/IBeetsSonicStaking.sol";

contract PendleBeetsStakedSonicSY is SYBaseUpg {
    address public constant SONIC_STAKING = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    constructor() SYBaseUpg(SONIC_STAKING) {
        _disableInitializers();
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY Beets Staked Sonic", "SY-stS");
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            return IBeetsSonicStaking(yieldToken).deposit{value: amountDeposited}();
        }
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        _transferOut(yieldToken, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public view virtual override returns (uint256 res) {
        return IERC4626(yieldToken).convertToAssets(1 ether);
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            return IERC4626(yieldToken).convertToShares(amountTokenToDeposit);
        }
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal view virtual override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, yieldToken);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == yieldToken;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldToken;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
