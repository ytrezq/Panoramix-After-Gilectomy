// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ISwapRouter } from "../../interfaces/ISwapRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface INeutrlRouter {
    /// @notice Mints NUSD using collateral
    /// @param _beneficiary Address that will receive the minted NUSD
    /// @param _collateralAsset Address of the collateral asset
    /// @param _collateralAmount Amount of collateral to deposit
    /// @param _minNusdAmount Minimum amount of NUSD to receive (slippage protection)
    /// @param _additionalData Additional data for the order, in case of future use for minters / redeemers
    function mint(
        address _beneficiary,
        address _collateralAsset,
        uint256 _collateralAmount,
        uint256 _minNusdAmount,
        bytes calldata _additionalData
    ) external;
}

contract sNUSDSwapAdapter {

    // e.g. 0xa052883ebEe7354FC2Aa0f9c727E657FdeCa744a
    INeutrlRouter public immutable router;

    // e.g. 0xE556ABa6fe6036275Ec1f87eda296BE72C811BCE
    address public immutable nusd;

    constructor (address nusd_, INeutrlRouter _router) {
        nusd = nusd_;
        router = _router;
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        address sender = msg.sender;
        require(params.tokenOut == nusd, "UnexpectedTokenOut");

        SafeERC20.safeTransferFrom(IERC20(params.tokenIn), sender, address(this), params.amountIn);
        SafeERC20.forceApprove(IERC20(params.tokenIn), address(router), params.amountIn);

        uint256 before = IERC20(params.tokenOut).balanceOf(sender);
        router.mint(
            sender,
            params.tokenIn,
            params.amountIn,
            params.amountOutMinimum,
            bytes("")
        );
        return IERC20(params.tokenOut).balanceOf(sender) - before;
    }
}
