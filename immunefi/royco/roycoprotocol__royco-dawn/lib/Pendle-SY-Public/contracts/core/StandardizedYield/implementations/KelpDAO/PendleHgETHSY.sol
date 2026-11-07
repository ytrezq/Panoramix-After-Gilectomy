// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../SYBase.sol";
import "../../../../interfaces/IPExchangeRateOracle.sol";
import "../../../../interfaces/IERC4626.sol";
import "../../../../interfaces/KelpDAO/IKelpDepositPool.sol";
import "../../../../interfaces/KelpDAO/IKelpLRTConfig.sol";

contract PendleHgETHSY is SYBase {
    event SetNewExchangeRateOracle(address oracle);

    // solhint-disable immutable-vars-naming
    // solhint-disable const-name-snakecase
    address public constant ETH_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant hgETH = 0xc824A08dB624942c5E5F330d56530cD1598859fD;
    address public constant rsETH = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
    address public constant depositPool = 0x036676389e48133B63a802f8635AD39E752D375D;
    address public exchangeRateOracle = 0x7A05D25E91C478EFFd37Baf86730bB4B84bE1E32;

    constructor() SYBase("SY Kelp High Growth ETH", "SY-hgETH", hgETH) {
        _safeApproveInf(rsETH, hgETH);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual override returns (uint256) {
        if (tokenIn == hgETH) {
            return amountDeposited;
        } else {
            if (tokenIn == NATIVE) {
                IKelpDepositPool(depositPool).depositETH{value: amountDeposited}(
                    0,
                    "c05f6902ec7c7434ceb666010c16a63a2e3995aad11f1280855b26402194346b"
                );
                (amountDeposited, tokenIn) = (_selfBalance(rsETH), rsETH);
            }
            return IERC4626(hgETH).deposit(amountDeposited, address(this));
        }
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256) {
        _transferOut(hgETH, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return IERC4626(hgETH).convertToAssets(IPExchangeRateOracle(exchangeRateOracle).getExchangeRate());
    }

    function setExchangeRateOracle(address newOracle) external onlyOwner {
        exchangeRateOracle = newOracle;
        emit SetNewExchangeRateOracle(newOracle);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            (tokenIn, amountTokenToDeposit) = (
                rsETH,
                IKelpDepositPool(depositPool).getRsETHAmountToMint(ETH_TOKEN, amountTokenToDeposit)
            );
        }
        if (tokenIn == rsETH) {
            return IERC4626(hgETH).previewDeposit(amountTokenToDeposit);
        }
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 amountTokenOut) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return ArrayLib.create(rsETH, hgETH, NATIVE);
    }

    function getTokensOut() public view virtual override returns (address[] memory) {
        return ArrayLib.create(hgETH);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == rsETH || token == hgETH || token == NATIVE;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == hgETH;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
