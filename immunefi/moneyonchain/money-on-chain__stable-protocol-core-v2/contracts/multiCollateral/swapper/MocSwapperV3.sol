// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocUpgradable } from "../../governance/MocUpgradable.sol";
import { IMocSwapper } from "../../interfaces/IMocSwapper.sol";
import { IWrapper } from "../../interfaces/IWrapper.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDataProvider } from "../../interfaces/IDataProvider.sol";

/**
 * @title MocSwapperV3
 * @notice MocSwapper component to swap tokens using uniswapV3 protocol
 *
 */
contract MocSwapperV3 is IMocSwapper, MocUpgradable {
    address private constant COINBASE = address(0);
    // ------- Custom Errors -------
    error CoinbaseTransferFailed();
    error PartialSwap();

    // ------- Storage -------
    // uniswapV3 router contracts
    IV3SwapRouter public swapRouter;
    // coinbase RC20 wrapper. Used to swap coinbase on the exchange
    IWrapper public coinbaseWrapper;
    // swap fee for the exchange pool
    mapping(address tokenIn => mapping(address tokenOut => uint24 fee)) public fees;
    // this is used to limit the amount of tokens that can be swapped in a single operation
    mapping(address tokenIn => mapping(address tokenOut => IDataProvider maxAmountToSwapProvider))
        public maxAmountToSwapProviders;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice contract initializer
     * @param governorAddress_ address of the governor contract
     * @param pauserAddress_ address of the pauser contract
     * @param swapRouter_ address of the uniswapV3 router
     * @param coinbaseWrapper_ address of the coinbase wrapper contract
     */
    function initialize(
        address governorAddress_,
        address pauserAddress_,
        address swapRouter_,
        address coinbaseWrapper_
    ) external initializer {
        __MocUpgradable_init(governorAddress_, pauserAddress_);
        swapRouter = IV3SwapRouter(swapRouter_);
        coinbaseWrapper = IWrapper(coinbaseWrapper_);
    }

    /**
     * @inheritdoc IMocSwapper
     */
    function getSafeMaxAmountToSwap(address tokenIn_, address tokenOut_) public view returns (uint256) {
        (bytes32 maxAmountToSwap, bool has) = maxAmountToSwapProviders[tokenIn_][tokenOut_].peek();
        if (!has) revert MissingProviderData(address(maxAmountToSwapProviders[tokenIn_][tokenOut_]));
        return uint256(maxAmountToSwap);
    }

    /**
     * @inheritdoc IMocSwapper
     */
    function swapCoinbase(
        address tokenOut_,
        uint256 amountOutMin_,
        address recipient_
    ) external payable returns (uint256 amountOut) {
        coinbaseWrapper.deposit{ value: msg.value }();
        return _swapExactInput(COINBASE, tokenOut_, msg.value, amountOutMin_, recipient_);
    }

    /**
     * @inheritdoc IMocSwapper
     */
    function swapCoinbaseExactOutput(
        address tokenOut_,
        uint256 amountOut_,
        address recipient_
    ) external payable returns (uint256 amountIn) {
        coinbaseWrapper.deposit{ value: msg.value }();
        amountIn = _swapExactOutput(COINBASE, tokenOut_, amountOut_, msg.value, recipient_);
        // return excess coinbase
        if (msg.value > amountIn) {
            _unwrapAndTransfer(msg.value - amountIn, msg.sender);
        }
    }

    /**
     * @inheritdoc IMocSwapper
     */
    function swapRC20(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address recipient_
    ) external returns (uint256 amountOut) {
        SafeERC20.safeTransferFrom(IERC20(tokenIn_), msg.sender, address(this), amountIn_);
        bool unwrap = tokenOut_ == COINBASE;
        amountOut = _swapExactInput(tokenIn_, tokenOut_, amountIn_, amountOutMin_, unwrap ? address(this) : recipient_);

        if (unwrap) {
            _unwrapAndTransfer(amountOut, recipient_);
        }
    }

    /**
     * @inheritdoc IMocSwapper
     */
    function swapRC20ExactOutput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address recipient_
    ) external returns (uint256 amountIn) {
        SafeERC20.safeTransferFrom(IERC20(tokenIn_), msg.sender, address(this), amountInMax_);
        bool unwrap = tokenOut_ == COINBASE;
        amountIn = _swapExactOutput(tokenIn_, tokenOut_, amountOut_, amountInMax_, unwrap ? address(this) : recipient_);
        // return excess tokenIn
        if (amountInMax_ > amountIn) {
            // reset allowance to zero
            SafeERC20.forceApprove(IERC20(tokenIn_), address(swapRouter), 0);
            SafeERC20.safeTransfer(IERC20(tokenIn_), msg.sender, amountInMax_ - amountIn);
        }

        if (unwrap) {
            _unwrapAndTransfer(amountOut_, recipient_);
        }
    }

    /**
     * @notice Unwrap coinbase and transfer to recipient
     * @param amount Amount to unwrap and transfer
     * @param recipient Recipient address
     */
    function _unwrapAndTransfer(uint256 amount, address recipient) internal {
        coinbaseWrapper.withdraw(amount);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = address(recipient).call{ value: amount }("");
        if (!success) revert CoinbaseTransferFailed();
    }

    /**
     * @notice swap RC20 token method using exact input
     * @param tokenIn_ RC20 token to send. If address(0) use the coinbase wrapper
     * @param tokenOut_ RC20 token to receive. If address(0) use the coinbase wrapper
     * @param amountIn_ amount of tokens to swap
     * @param amountOutMin_ minimum amount of tokens to receive
     * @param recipient_ address who receives the tokens
     * @return amountOut amount of RC20 tokens received
     */
    function _swapExactInput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address recipient_
    ) internal returns (uint256 amountOut) {
        address tokenIn = tokenIn_ == COINBASE ? address(coinbaseWrapper) : tokenIn_;
        SafeERC20.forceApprove(IERC20(tokenIn), address(swapRouter), amountIn_);
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut_ == COINBASE ? address(coinbaseWrapper) : tokenOut_,
            fee: fees[tokenIn_][tokenOut_],
            recipient: recipient_,
            amountIn: amountIn_,
            amountOutMinimum: amountOutMin_,
            sqrtPriceLimitX96: 0
        });

        uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));

        // Execute the swap
        amountOut = swapRouter.exactInputSingle(params);

        if (IERC20(tokenIn).balanceOf(address(this)) != balanceBefore - amountIn_) revert PartialSwap();
    }

    /**
     * @notice swap RC20 token method using exact output
     * @param tokenIn_ RC20 token to send. If address(0) use the coinbase wrapper
     * @param tokenOut_ RC20 token to receive. If address(0) use the coinbase wrapper
     * @param amountOut_ amount of tokens to receive in the swap
     * @param amountInMax_ maximum amount of tokens to spend
     * @param recipient_ address who receives the tokens
     * @return amountIn amount of RC20 tokens spent
     */
    function _swapExactOutput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address recipient_
    ) internal returns (uint256 amountIn) {
        address tokenIn = tokenIn_ == COINBASE ? address(coinbaseWrapper) : tokenIn_;
        address tokenOut = tokenOut_ == COINBASE ? address(coinbaseWrapper) : tokenOut_;
        SafeERC20.forceApprove(IERC20(tokenIn), address(swapRouter), amountInMax_);
        IV3SwapRouter.ExactOutputSingleParams memory params = IV3SwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fees[tokenIn_][tokenOut_],
            recipient: recipient_,
            amountOut: amountOut_,
            amountInMaximum: amountInMax_,
            sqrtPriceLimitX96: 0
        });

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient_);

        // Execute the swap
        amountIn = swapRouter.exactOutputSingle(params);

        // NOTICE: When using a standard Uniswap Router, exactOutput reverts before this does.
        // but we keep this here defensively, it's worth the gas.
        if (IERC20(tokenOut).balanceOf(recipient_) != balanceBefore + amountOut_) revert PartialSwap();
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @notice set a pool to the swapper
     * @param tokenA_ address of the first token. For coinbase use address(0)
     * @param tokenB_ address of the second token. For coinbase use address(0)
     * @param fee_ fee of the pool
     * @param providerSwappingAtoB_ address of the max amount to swap provider for the tokenA -> tokenB pool
     */
    function setPool(
        address tokenA_,
        address tokenB_,
        uint24 fee_,
        IDataProvider providerSwappingAtoB_
    ) external onlyAuthorizedChanger {
        maxAmountToSwapProviders[tokenA_][tokenB_] = providerSwappingAtoB_;
        fees[tokenA_][tokenB_] = fee_;
    }

    // @notice used to receive coinbase to unwrap it
    receive() external payable {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
