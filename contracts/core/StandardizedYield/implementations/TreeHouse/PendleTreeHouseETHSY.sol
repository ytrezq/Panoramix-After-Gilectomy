// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/IWstETH.sol";
import "../../../../interfaces/IStETH.sol";
import "../../../../interfaces/IERC4626.sol";
import "../../../../interfaces/IPTokenWithSupplyCap.sol";
import "../../../../interfaces/TreeHouse/ITreeHouseRouter.sol";
import "../../../../interfaces/TreeHouse/ITreeHouseFastLane.sol";
import "../../../../interfaces/TreeHouse/ITreeHouseFastLaneFee.sol";

contract PendleTreeHouseETHSY is SYBaseUpg, IPTokenWithSupplyCap {
    // solhint-disable immutable-vars-naming
    address public constant TREEHOUSE_ROUTER = 0xeFA3fa8e85D2b3CfdB250CdeA156c2c6C90628F5;
    address public constant TREEHOUSE_FASTLANE = 0x829525417Cd78CBa0f99A8736426fC299506C0d6;
    address public constant TREEHOUSE_FASTLANE_FEE = 0x434B68B11bBE8FD3074089397cA3d275801d6354;

    address public constant TETH = 0xD11c452fc99cF405034ee446803b6F6c1F6d5ED8;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    constructor() SYBaseUpg(TETH) {}

    function initialize() external initializer {
        __SYBaseUpg_init("SY Treehouse ETH", "SY tETH");
        _safeApproveInf(WSTETH, TREEHOUSE_ROUTER);
        _safeApproveInf(STETH, TREEHOUSE_ROUTER);
        _safeApproveInf(TETH, TREEHOUSE_FASTLANE);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual override returns (uint256) {
        if (tokenIn != TETH) {
            uint256 preBalance = _selfBalance(TETH);
            if (tokenIn == NATIVE) {
                ITreeHouseRouter(TREEHOUSE_ROUTER).depositETH{value: amountDeposited}();
            } else {
                ITreeHouseRouter(TREEHOUSE_ROUTER).deposit(tokenIn, amountDeposited);
            }
            return _selfBalance(TETH) - preBalance;
        }
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        if (tokenOut != TETH) {
            ITreeHouseFastLane(TREEHOUSE_FASTLANE).redeemAndFinalize(PMath.Uint96(amountSharesToRedeem));
            uint256 amountWstETH = _selfBalance(WSTETH);

            if (tokenOut == STETH) {
                amountTokenOut = IWstETH(WSTETH).unwrap(amountWstETH);
            } else {
                amountTokenOut = amountWstETH;
            }
        } else {
            amountTokenOut = amountSharesToRedeem;
        }

        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return IStETH(STETH).getPooledEthByShares(IERC4626(TETH).convertToAssets(1 ether));
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == TETH) {
            return amountTokenToDeposit;
        }
        if (tokenIn == NATIVE || tokenIn == STETH) {
            (tokenIn, amountTokenToDeposit) = (WSTETH, IStETH(STETH).getSharesByPooledEth(amountTokenToDeposit));
        }
        return IERC4626(TETH).previewDeposit(amountTokenToDeposit);
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        if (tokenOut == TETH) {
            return amountSharesToRedeem;
        }

        uint256 amountWstETH = IERC4626(TETH).previewRedeem(amountSharesToRedeem);
        amountWstETH -= ITreeHouseFastLaneFee(TREEHOUSE_FASTLANE_FEE).applyFee(amountWstETH);

        if (tokenOut == WSTETH) {
            return amountWstETH;
        } else {
            return IStETH(STETH).getPooledEthByShares(amountWstETH);
        }
    }

    function getTokensIn() public pure override returns (address[] memory res) {
        return ArrayLib.create(STETH, WSTETH, NATIVE, TETH);
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        return ArrayLib.create(STETH, WSTETH, TETH);
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == STETH || token == WSTETH || token == NATIVE || token == TETH;
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return token == STETH || token == WSTETH || token == TETH;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = STETH;
        assetDecimals = IERC20Metadata(STETH).decimals();
    }

    function getAbsoluteSupplyCap() external view returns (uint256) {
        uint256 capInETH = ITreeHouseRouter(TREEHOUSE_ROUTER).depositCapInEth();
        return IERC4626(TETH).convertToShares(IStETH(STETH).getSharesByPooledEth(capInETH));
    }

    function getAbsoluteTotalSupply() external view returns (uint256) {
        return IERC4626(TETH).convertToShares(IERC20(IERC4626(TETH).asset()).totalSupply());
    }
}
