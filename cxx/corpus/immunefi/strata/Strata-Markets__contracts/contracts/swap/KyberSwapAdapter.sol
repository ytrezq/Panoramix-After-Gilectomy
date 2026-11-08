// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapAdapter} from "./interfaces/ISwapAdapter.sol";

/// @title KyberSwapAdapter
/// @notice Stateless adapter that executes token swaps via a KyberSwap router.
///         Access control is enforced by the calling contract (e.g. Strategy).
contract KyberSwapAdapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error SwapFailed(string reason);

    event SwapExecuted(
        address indexed router,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @inheritdoc ISwapAdapter
    function swap(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient,
        bytes calldata data,
        uint256 value
    ) external payable returns (uint256 amountOut) {
        if (router == address(0) || recipient == address(0)) revert ZeroAddress();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(router, amountIn);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);

        (bool success, bytes memory returndata) = router.call{value: value}(data);
        if (!success) {
            if (returndata.length >= 68 && bytes4(returndata) == 0x08c379a0) {
                revert SwapFailed(_getRevertMsg(returndata));
            }
            revert SwapFailed("SwapFailed");
        }

        amountOut = IERC20(tokenOut).balanceOf(recipient) - balanceBefore;

        // Return any unspent input tokens to the caller
        uint256 remaining = IERC20(tokenIn).balanceOf(address(this));
        if (remaining > 0) {
            IERC20(tokenIn).safeTransfer(msg.sender, remaining);
        }

        emit SwapExecuted(router, tokenIn, tokenOut, amountIn, amountOut);
    }

    receive() external payable {}

    function _getRevertMsg(bytes memory revertData) internal pure returns (string memory) {
        assembly {
            revertData := add(revertData, 0x04)
        }
        return abi.decode(revertData, (string));
    }
}
