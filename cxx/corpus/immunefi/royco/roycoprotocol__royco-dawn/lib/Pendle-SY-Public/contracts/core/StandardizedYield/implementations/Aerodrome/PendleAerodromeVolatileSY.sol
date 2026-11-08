// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./PendleAerodromeZapHelper.sol";
import "./PendleAerodromeVolatilePreview.sol";

import "../../SYBaseWithRewardsUpg.sol";
import "../../../../interfaces/Aerodrome/IAerodromeGauge.sol";

contract PendleAerodromeVolatileSY is SYBaseWithRewardsUpg, PendleAerodromeZapHelper {
    address public immutable gauge;
    address public immutable rewardToken;
    address public immutable previewHelper;

    constructor(
        address _router,
        address _gauge,
        address _previewHelper
    )
        PendleAerodromeZapHelper(_router, IAerodromeGauge(_gauge).stakingToken())
        SYBaseUpg(IAerodromeGauge(_gauge).stakingToken())
    {
        gauge = _gauge;
        rewardToken = IAerodromeGauge(_gauge).rewardToken();
        previewHelper = _previewHelper;

        require(IAerodromePool(pool).stable() == false, "AV-SY: Invalid pool");
    }

    function initialize(string memory _name, string memory _symbol) external initializer {
        __SYBaseUpg_init(_name, _symbol);
        _safeApproveInf(pool, gauge);
        _safeApproveInf(pool, router);
        _safeApproveInf(token0, router);
        _safeApproveInf(token1, router);
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual override returns (uint256) {
        uint256 amountLpOut;
        if (tokenIn != pool) {
            amountLpOut = _zapIn(tokenIn, amountDeposited);
        } else {
            amountLpOut = amountDeposited;
        }
        IAerodromeGauge(gauge).deposit(amountLpOut);
        return amountLpOut;
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        IAerodromeGauge(gauge).withdraw(amountSharesToRedeem);
        if (tokenOut != pool) {
            amountTokenOut = _zapOut(tokenOut, amountSharesToRedeem);
        } else {
            amountTokenOut = amountSharesToRedeem;
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == pool) {
            return amountTokenToDeposit;
        }
        return PendleAerodromeVolatilePreview(previewHelper).previewZapIn(pool, tokenIn, amountTokenToDeposit);
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        if (tokenOut == pool) {
            return amountSharesToRedeem;
        }
        return PendleAerodromeVolatilePreview(previewHelper).previewZapOut(pool, tokenOut, amountSharesToRedeem);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return PMath.ONE;
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    function _getRewardTokens() internal view override returns (address[] memory res) {
        return ArrayLib.create(rewardToken);
    }

    function _redeemExternalReward() internal override {
        IAerodromeGauge(gauge).getReward(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function getTokensIn() public view virtual override returns (address[] memory res) {
        return ArrayLib.create(token0, token1, pool);
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        return ArrayLib.create(token0, token1, pool);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1 || token == pool;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1 || token == pool;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.LIQUIDITY, pool, IERC20Metadata(pool).decimals());
    }
}
