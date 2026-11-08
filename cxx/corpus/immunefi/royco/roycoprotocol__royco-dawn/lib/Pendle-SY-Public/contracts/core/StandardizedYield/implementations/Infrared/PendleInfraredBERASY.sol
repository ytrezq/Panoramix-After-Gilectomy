// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/Infrared/IInfraredBERA.sol";

contract PendleInfraredBERASY is SYBaseUpg {
    address public constant IBERA = 0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5;
    address public constant FEE_RECEIVOR = 0xf6a4A6aCECd5311327AE3866624486b6179fEF97;

    constructor() SYBaseUpg(IBERA) {}

    function initialize() external initializer {
        __SYBaseUpg_init("SY Infrared BERA", "SY-iBERA");
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            return IInfraredBERA(IBERA).mint{value: amountDeposited}(address(this));
        }
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        _transferOut(IBERA, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public view virtual override returns (uint256) {
        (uint256 compoundAmount, ) = IInfraredBeraFeeReceivor(FEE_RECEIVOR).distribution();
        uint256 ts = IERC20(IBERA).totalSupply();
        uint256 ta = IInfraredBERA(IBERA).deposits();
        return PMath.divDown(ta + compoundAmount, ts);
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            return IInfraredBERA(IBERA).previewMint(amountTokenToDeposit);
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
        return ArrayLib.create(NATIVE, IBERA);
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        return ArrayLib.create(IBERA);
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return token == IBERA || token == NATIVE;
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return token == IBERA;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
