// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/Lista/IListaStakeManager.sol";
import "../../../../interfaces/Astherus/IAstherusBnbMinter.sol";
import "../../../../interfaces/Astherus/IAstherusBnbYieldProxy.sol";

contract PendleAsBNBSY is SYBaseUpg {
    using PMath for uint256;

    error AstherusYieldProxyActivitiesOnGoing();

    uint256 public constant FEE_DENOMINATOR = 10000;

    address public constant LISTA_STAKE_MANAGER = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;
    address public constant MINTER = 0x2F31ab8950c50080E77999fa456372f276952fD8;
    address public constant SLIS_BNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;
    address public constant ASBNB = 0x77734e70b6E88b4d82fE632a168EDf6e700912b6;
    address public constant YIELD_PROXY = 0xE861dd4b0AB6f3a42943e6EF441c3C611CD1bec2;

    constructor() SYBaseUpg(ASBNB) {
        assert(block.chainid == 56);
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY Astherus BNB", "SY-asBNB");
        _safeApproveInf(SLIS_BNB, MINTER);
        _safeApproveInf(ASBNB, MINTER);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == ASBNB) {
            return amountDeposited;
        }

        // Logically equivalent of checking output > 0
        // if (IAstherusBnbYieldProxy(YIELD_PROXY).activitiesOnGoing()) {
        //     revert AstherusYieldProxyActivitiesOnGoing();
        // }
        if (tokenIn == NATIVE) {
            amountSharesOut = IAstherusBnbMinter(MINTER).mintAsBnb{value: amountDeposited}();
        } else if (tokenIn == SLIS_BNB) {
            amountSharesOut = IAstherusBnbMinter(MINTER).mintAsBnb(amountDeposited);
        }

        if (amountSharesOut == 0) {
            revert AstherusYieldProxyActivitiesOnGoing();
        }
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        if (tokenOut != ASBNB) {
            uint256 preBalance = _selfBalance(SLIS_BNB);
            IAstherusBnbMinter(MINTER).burnAsBnb(amountSharesToRedeem);
            amountTokenOut = _selfBalance(SLIS_BNB) - preBalance;
        } else {
            amountTokenOut = amountSharesToRedeem;
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return
            IListaStakeManager(LISTA_STAKE_MANAGER).convertSnBnbToBnb(
                IAstherusBnbMinter(MINTER).convertToTokens(1 ether)
            );
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == ASBNB) {
            return amountTokenToDeposit;
        } else {
            if (IAstherusBnbYieldProxy(YIELD_PROXY).activitiesOnGoing()) {
                revert AstherusYieldProxyActivitiesOnGoing();
            }

            if (tokenIn == NATIVE) {
                (tokenIn, amountTokenToDeposit) = (
                    SLIS_BNB,
                    IListaStakeManager(LISTA_STAKE_MANAGER).convertBnbToSnBnb(amountTokenToDeposit)
                );
            }
            return IAstherusBnbMinter(MINTER).convertToAsBnb(amountTokenToDeposit);
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        if (tokenOut == SLIS_BNB) {
            uint256 rawAmtOut = IAstherusBnbMinter(MINTER).convertToTokens(amountSharesToRedeem);
            return rawAmtOut - (rawAmtOut * IAstherusBnbMinter(MINTER).withdrawalFeeRate()) / FEE_DENOMINATOR;
        } else {
            return amountSharesToRedeem;
        }
    }

    function getTokensIn() public pure override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, SLIS_BNB, ASBNB);
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        return ArrayLib.create(SLIS_BNB, ASBNB);
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == NATIVE || token == SLIS_BNB || token == ASBNB;
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return token == SLIS_BNB || token == ASBNB;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
