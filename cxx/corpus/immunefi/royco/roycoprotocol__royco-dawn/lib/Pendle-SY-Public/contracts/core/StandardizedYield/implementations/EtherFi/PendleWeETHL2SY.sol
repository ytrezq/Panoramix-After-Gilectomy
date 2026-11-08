// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "../PendleERC20SYUpg.sol";
import "../../../../interfaces/EtherFi/IEtherFiL2Pool.sol";
import "../../../../interfaces/EtherFi/IEtherFiExchangeRateProvider.sol";
import "../../../../interfaces/IPExchangeRateOracle.sol";

contract PendleWeETHL2SY is PendleERC20SYUpg {
    using PMath for uint256;

    address public constant EETH_L1 = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;

    address public immutable l2Pool;
    address public immutable weth;
    address public immutable oracle;

    constructor(
        address _l2Pool,
        address _weth,
        address _oracle
    ) PendleERC20SYUpg(IEtherFiL2Pool(_l2Pool).getTokenOut()) {
        l2Pool = _l2Pool;
        weth = _weth;
        oracle = _oracle;
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY ether.fi weETH", "SY-weETH");
        _safeApproveInf(weth, l2Pool);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn != yieldToken) {
            return IEtherFiL2Pool(l2Pool).deposit(tokenIn, amountDeposited, 0);
        } else {
            return amountDeposited;
        }
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 amountSharesOut) {
        if (tokenIn != yieldToken) {
            // this function is expected to be used fully off-chain
            return
                IEtherFiExchangeRateProvider(IEtherFiL2Pool(l2Pool).getL2ExchangeRateProvider()).getConversionAmount(
                    tokenIn,
                    amountTokenToDeposit
                );
        } else {
            return amountTokenToDeposit;
        }
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldToken || token == weth;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(weth, yieldToken);
    }

    /// =================================================================

    function exchangeRate() public view virtual override returns (uint256) {
        return IPExchangeRateOracle(oracle).getExchangeRate();
    }

    function assetInfo()
        external
        pure
        override
        returns (AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (AssetType.TOKEN, EETH_L1, 18);
    }
}
