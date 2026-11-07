// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/Lista/IListaStakeManager.sol";
import "../../../../interfaces/Lista/IListaClisBNBSwap.sol";
import "../../../../interfaces/Lista/IListaDAO.sol";

contract PendleClisBNBSY is SYBaseUpg {
    address public constant LISTA_STAKE_MANAGER = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;
    address public constant SLIS_BNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;
    address public constant CLIS_BNB_SWAP = 0xfD31e1C5e5571f8E7FE318f80888C1e6da97819b;

    address public constant DELEGATEE = 0xb1E6d401a202335403A6d19b9C2aC185605DC64B;

    constructor() SYBaseUpg(SLIS_BNB) {}

    function initialize() external initializer {
        __SYBaseUpg_init("SY Lista collateral BNB", "SY-clisBNB");
        _safeApproveInf(SLIS_BNB, CLIS_BNB_SWAP);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            IListaStakeManager(LISTA_STAKE_MANAGER).deposit{value: amountDeposited}();
            amountDeposited = _selfBalance(SLIS_BNB);
        }

        IListaClisBNBSwap(CLIS_BNB_SWAP).provide(amountDeposited, DELEGATEE);

        // only matters how much slisbnb is in dao
        // provider.exchangeRate() is only increasing (1 slisBNB >>> clisBNB over time)
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        IListaClisBNBSwap(CLIS_BNB_SWAP).release(receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return IListaStakeManager(LISTA_STAKE_MANAGER).convertSnBnbToBnb(1 ether);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            return IListaStakeManager(LISTA_STAKE_MANAGER).convertBnbToSnBnb(amountTokenToDeposit);
        }
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public pure override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, SLIS_BNB);
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        return ArrayLib.create(SLIS_BNB);
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == NATIVE || token == SLIS_BNB;
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return token == SLIS_BNB;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
