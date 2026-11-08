// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocUpgradable } from "../../governance/MocUpgradable.sol";
import { IMocSwapper } from "../../interfaces/IMocSwapper.sol";
import { IPermit2 } from "../../interfaces/IPermit2.sol";
import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PathKey } from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { Commands } from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDataProvider } from "../../interfaces/IDataProvider.sol";

/**
 * @title MocSwapperV4MultiHop
 * @notice MocSwapper component to swap tokens using uniswapV4 protocol
 *
 */
contract MocSwapperV4MultiHop is IMocSwapper, MocUpgradable {
    uint256 public constant DEADLINE = 20;
    // ------- Custom Errors -------
    error WrongLength();
    error PartialSwap();

    // ------- Storage -------
    // uniswap universal router
    IUniversalRouter public universalRouter;
    // handle token allowances for transfers through the universal router
    IPermit2 public permit2;
    // tokenIn => tokenOut => pathKeys
    mapping(Currency tokenIn => mapping(Currency tokenOut => PathKey[] pathKeys)) public pathKeys;
    // this is used to limit the amount of tokens that can be swapped in a single operation
    mapping(address tokenIn => mapping(address tokenOut => IDataProvider maxAmountToSwapProvider))
        public maxAmountToSwapProviders;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializer
     * @param governorAddress_ address of the governor contract
     * @param pauserAddress_ address of the pauser contract
     * @param universalRouter_ address of the uniswapV4 router
     * @param permit2_ address of the permit2 contract
     */
    function initialize(
        address governorAddress_,
        address pauserAddress_,
        address universalRouter_,
        address permit2_
    ) external initializer {
        __MocUpgradable_init(governorAddress_, pauserAddress_);
        universalRouter = IUniversalRouter(universalRouter_);
        permit2 = IPermit2(permit2_);
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
        return _swapExactInput(Constants.ETH, tokenOut_, msg.value, amountOutMin_, recipient_);
    }

    /**
     * @inheritdoc IMocSwapper
     */
    function swapCoinbaseExactOutput(
        address tokenOut_,
        uint256 amountOut_,
        address recipient_
    ) external payable returns (uint256 amountIn) {
        return _swapExactOutput(Constants.ETH, tokenOut_, amountOut_, msg.value, recipient_);
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
        SafeERC20.forceApprove(IERC20(tokenIn_), address(permit2), amountIn_);
        permit2.approve(tokenIn_, address(universalRouter), uint160(amountIn_), uint48(block.timestamp));
        return _swapExactInput(tokenIn_, tokenOut_, amountIn_, amountOutMin_, recipient_);
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
        SafeERC20.forceApprove(IERC20(tokenIn_), address(permit2), amountInMax_);
        permit2.approve(tokenIn_, address(universalRouter), uint160(amountInMax_), uint48(block.timestamp));
        amountIn = _swapExactOutput(tokenIn_, tokenOut_, amountOut_, amountInMax_, recipient_);
    }

    /**
     * @notice swap RC20 token using exact input (multi-hop)
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
        Currency currencyIn = Currency.wrap(tokenIn_);
        Currency currencyOut = Currency.wrap(tokenOut_);

        // encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // encode V4Router actions
        bytes memory actions = abi.encodePacked(
            // this action specifies that we want to perform an exact input swap using a path key
            uint8(Actions.SWAP_EXACT_IN),
            // this action ensures all input tokens involved in the swap are properly paid
            uint8(Actions.SETTLE_ALL),
            // this final action collects all output tokens after the swap is complete
            uint8(Actions.TAKE_ALL)
        );

        // prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: currencyIn,
                path: pathKeys[currencyIn][currencyOut],
                amountIn: uint128(amountIn_),
                amountOutMinimum: uint128(amountOutMin_)
            })
        );
        params[1] = abi.encode(tokenIn_, amountIn_);
        params[2] = abi.encode(tokenOut_, amountOutMin_);

        // combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        uint256 balanceInBefore = currencyIn.balanceOfSelf();
        uint256 balanceOutBefore = currencyOut.balanceOfSelf();

        // execute the swap
        // use recommended deadline: https://docs.uniswap.org/contracts/v4/quickstart/swap#35-executing-the-swap
        universalRouter.execute{ value: msg.value }(commands, inputs, block.timestamp + DEADLINE);

        // We must defensively check the swap behaved as expected, spending the full amount and
        // returning at least the required amount.
        uint256 balanceInAfter = currencyIn.balanceOfSelf();
        if (balanceInAfter != balanceInBefore - amountIn_) revert PartialSwap();

        uint256 balanceOutAfter = currencyOut.balanceOfSelf();
        // transfer only the amount produced by this swap, not the full contract balance
        amountOut = balanceOutAfter - balanceOutBefore;
        currencyOut.transfer(recipient_, amountOut);
    }

    /**
     * @notice swap RC20 token using exact output (multi-hop)
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
        Currency currencyIn = Currency.wrap(tokenIn_);
        Currency currencyOut = Currency.wrap(tokenOut_);

        // encode the Universal Router command
        bytes memory commands = abi.encodePacked(
            // this command specifies that we want to perform a V4 swap
            uint8(Commands.V4_SWAP),
            // // this command specifies that we want to sweep any remaining tokenIn back
            uint8(Commands.SWEEP)
        );
        bytes[] memory inputs = new bytes[](2);

        // encode V4Router actions
        bytes memory actions = abi.encodePacked(
            // this action specifies that we want to perform an exact output swap using a path key
            uint8(Actions.SWAP_EXACT_OUT),
            // this action ensures all input tokens involved in the swap are properly paid
            uint8(Actions.SETTLE_ALL),
            // this final action collects all output tokens after the swap is complete
            uint8(Actions.TAKE_ALL)
        );

        // prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputParams({
                currencyOut: currencyOut,
                path: pathKeys[currencyOut][currencyIn],
                amountOut: uint128(amountOut_),
                amountInMaximum: uint128(amountInMax_)
            })
        );
        params[1] = abi.encode(tokenIn_, amountInMax_);
        params[2] = abi.encode(tokenOut_, amountOut_);

        // combine actions and params into inputs for the swap command
        inputs[0] = abi.encode(actions, params);
        // params for the sweep command
        inputs[1] = abi.encode(tokenIn_, address(this));

        uint256 balanceInBefore = currencyIn.balanceOfSelf();
        uint256 balanceOutBefore = currencyOut.balanceOfSelf();

        // execute the swap and the sweep
        universalRouter.execute{ value: msg.value }(commands, inputs, block.timestamp + DEADLINE);

        // We must defensively check the swap behaved as expected, returning at least the required amount.
        uint256 balanceOutAfter = currencyOut.balanceOfSelf();
        if (balanceOutAfter != balanceOutBefore + amountOut_) revert PartialSwap();

        uint256 balanceInAfter = currencyIn.balanceOfSelf();

        amountIn = balanceInBefore - balanceInAfter;
        uint256 surplus = amountInMax_ - amountIn;
        // transfer tokenOut to the recipient
        currencyOut.transfer(recipient_, amountOut_);
        // transfer tokenIn back to the sender
        currencyIn.transfer(msg.sender, surplus);
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @notice sets a path to the swapper
     * @dev for example, if tokenA = WETH, tokenB = USDC, intermediateTokens = [DOC, USDT], fees = [3000, 500, 500]
     * the path will be: WETH -> DOC (3000) -> USDT (500) -> USDC (500)
     * @param tokenA_ address of the first token
     * @param tokenB_ address of the second token
     * @param intermediateTokens_ array of intermediate tokens
     * @param fees_ array of fees for each intermediate token
     * @param tickSpacings_ array of tick spacings for each intermediate token
     * @param hooks_ array of hooks for each intermediate token
     * @param providerSwappingAtoB_ address of the max amount to swap provider for the tokenA -> tokenB pool
     */
    function setPath(
        Currency tokenA_,
        Currency tokenB_,
        Currency[] memory intermediateTokens_,
        uint24[] memory fees_,
        int24[] memory tickSpacings_,
        IHooks[] memory hooks_,
        IDataProvider providerSwappingAtoB_
    ) external onlyAuthorizedChanger {
        uint256 length = fees_.length;
        if (length != intermediateTokens_.length + 1 || length != tickSpacings_.length || length != hooks_.length)
            revert WrongLength();

        PathKey[] memory path = new PathKey[](length);

        // path: tokenA -> intermediates -> tokenB
        for (uint256 i = 0; i < length; i++) {
            Currency currency = (i < intermediateTokens_.length) ? intermediateTokens_[i] : tokenB_;
            path[i] = PathKey({
                intermediateCurrency: currency,
                fee: fees_[i],
                tickSpacing: tickSpacings_[i],
                hooks: hooks_[i],
                hookData: bytes("") // no hook data needed
            });
        }

        pathKeys[tokenA_][tokenB_] = path;
        maxAmountToSwapProviders[Currency.unwrap(tokenA_)][Currency.unwrap(tokenB_)] = providerSwappingAtoB_;
    }

    // @notice used to receive coinbase
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
