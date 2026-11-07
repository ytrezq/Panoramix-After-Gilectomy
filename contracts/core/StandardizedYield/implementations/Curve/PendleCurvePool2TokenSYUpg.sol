// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./PendleCurve2TokenLib.sol";
import "../../SYBaseWithRewardsUpg.sol";
import "../../../../interfaces/Curve/ICurveGauge.sol";
import "../../../../interfaces/Curve/ICurvePoolDynamic.sol";
import "../../../../interfaces/Curve/ICurveMinter.sol";

contract PendleCurvePool2TokenSYUpg is SYBaseWithRewardsUpg {
    using PMath for uint256;

    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    // solhint-disable immutable-vars-naming
    address public immutable lp;
    address public immutable gauge;

    address public immutable token0;
    address public immutable token1;

    constructor(address _gauge) SYBaseUpg(_gauge) {
        gauge = _gauge;
        lp = ICurveGauge(_gauge).lp_token();
        token0 = ICurvePoolDynamic(lp).coins(0);
        token1 = ICurvePoolDynamic(lp).coins(1);
    }

    function initialize(string memory _name, string memory _symbol) external initializer {
        __SYBaseUpg_init(_name, _symbol);
        _safeApproveInf(lp, gauge);
        _safeApproveInf(token0, lp);
        _safeApproveInf(token1, lp);
    }

    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual override returns (uint256) {
        if (tokenIn == token0 || tokenIn == token1) {
            (tokenIn, amountDeposited) = (
                lp,
                ICurvePoolDynamic(lp).add_liquidity(__getCurveAmounts(tokenIn, amountDeposited), 0)
            );
        }
        if (tokenIn == lp) {
            ICurveGauge(gauge).deposit(amountDeposited);
        }
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        amountTokenOut = amountSharesToRedeem;
        if (tokenOut != gauge) {
            ICurveGauge(gauge).withdraw(amountSharesToRedeem);
        }
        if (tokenOut != lp && tokenOut != gauge) {
            amountTokenOut = ICurvePoolDynamic(lp).remove_liquidity_one_coin(
                amountSharesToRedeem,
                __getCurveTokenId(tokenOut),
                0,
                receiver
            );
        } else {
            _transferOut(tokenOut, receiver, amountTokenOut);
        }
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        // This is subjected to Curve's known issue of re-entrancy. Be cautious on pool with raw ETH, token with transfer hook,...
        return ICurvePoolDynamic(lp).get_virtual_price();
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function _getRewardTokens() internal pure override returns (address[] memory) {
        // TBD
        return ArrayLib.create(CRV);
    }

    function _redeemExternalReward() internal override {
        // ICurveGauge(gauge).claim_rewards();
        ICurveMinter(MINTER).mint(gauge);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        if (tokenIn == lp || tokenIn == gauge) {
            return amountTokenToDeposit;
        }
        return PendleCurve2TokenLib.previewAddLiquidity(lp, tokenIn, amountTokenToDeposit);
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        if (tokenOut == lp || tokenOut == gauge) {
            return amountSharesToRedeem;
        }
        return ICurvePoolDynamic(lp).calc_withdraw_one_coin(amountSharesToRedeem, __getCurveTokenId(tokenOut));
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return ArrayLib.create(token0, token1, lp, gauge);
    }

    function getTokensOut() public view virtual override returns (address[] memory) {
        return ArrayLib.create(token0, token1, lp, gauge);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1 || token == lp || token == gauge;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1 || token == lp || token == gauge;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        // The definition here implies that 1 SY = 1 LP with no direct correlation between price and exchangeRate()
        return (AssetType.LIQUIDITY, lp, 18);
    }

    function __getCurveAmounts(address token, uint256 amount) internal view returns (uint256[] memory) {
        return ArrayLib.create(token == token0 ? amount : 0, token == token1 ? amount : 0);
    }

    function __getCurveTokenId(address token) internal view returns (int128) {
        return (token == token0 ? int128(0) : int128(1));
    }
}
