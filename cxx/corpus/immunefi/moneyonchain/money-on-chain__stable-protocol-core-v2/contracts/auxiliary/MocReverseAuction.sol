// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Governed, IGovernor } from "../governance/Governed.sol";
import { IMocSwapper } from "../interfaces/IMocSwapper.sol";
import { IPriceProvider } from "../interfaces/IPriceProvider.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title MocReverseAuction
 * @notice This contract accumulates tokens, swaps them for a different token,
 *  and transfers the resulting tokens to a specified address.
 */
contract MocReverseAuction is Governed, ReentrancyGuard {
    address private constant COINBASE = address(0);
    // ------- Events -------
    event EmergencyWithdraw(address token_, address to_, uint256 amount_);
    event Triggered(address tokenIn_, address tokenOut_, uint256 amountIn_, uint256 amountOut_, address outputAccount_);
    // ------- Custom Errors -------
    error NotCoinbase();
    error TransferFailed();
    error InvalidSlippage();

    // ------- Storage -------
    // MocSwapper contract used to swap the tokens
    IMocSwapper public mocSwapper;
    // token to accumulate and swap
    address public tokenIn;
    // token to receive in the swap
    address public tokenOut;
    // address who receives the swapped token
    address public outputAccount;
    // minimum amount of tokenIn that justifies trigger exchange orders
    uint256 public orderThreshold;
    // tokenIn/tokenOut price provider used to compute amountOutMin
    IPriceProvider public priceProvider;
    // slippage as a percentage with 18 decimals. 1 * 1e18 means 100%.
    uint256 public slippage;

    /**
     * @notice constructor
     * @param governor_ address of the governor contract
     * @param mocSwapper_ address of the MocSwapper contract
     * @param tokenIn_ token to accumulate and swap
     * @param tokenOut_ token to receive in the swap
     * @param outputAccount_ address who receives the swapped token
     * @param orderThreshold_ minimum amount of tokenIn that justifies trigger exchange orders
     */
    constructor(
        address governor_,
        address mocSwapper_,
        address tokenIn_,
        address tokenOut_,
        address outputAccount_,
        uint256 orderThreshold_,
        address priceProvider_,
        uint256 slippage_
    ) {
        _disableInitializers();
        governor = IGovernor(governor_);
        mocSwapper = IMocSwapper(mocSwapper_);
        tokenIn = tokenIn_;
        tokenOut = tokenOut_;
        outputAccount = outputAccount_;
        orderThreshold = orderThreshold_;
        priceProvider = IPriceProvider(priceProvider_);
        _setSlippage(slippage_);
    }

    /**
     *@notice transfer tokens to the given address
     *@param token_ address of the token to be transferred
     *@param to_ address of the recipient
     *@param amount_ amount of tokens to be transferred
     */
    function _transfer(address token_, address to_, uint256 amount_) internal {
        if (amount_ > 0 && to_ != address(0)) {
            if (token_ == COINBASE) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, ) = to_.call{ value: amount_ }("");
                if (!success) revert TransferFailed();
            } else {
                SafeERC20.safeTransfer(IERC20(token_), to_, amount_);
            }
        }
    }

    /**
     * @notice get the balance of the contract
     * @param token_ address of the token
     * @return balance of the contract
     */
    function _balanceOfSelf(address token_) internal view returns (uint256) {
        if (token_ == COINBASE) {
            return address(this).balance;
        } else {
            return IERC20(token_).balanceOf(address(this));
        }
    }

    /**
     * @notice get the balance of the contract
     * @return balance of the contract
     */
    function balanceOfSelf() external view returns (uint256) {
        return _balanceOfSelf(tokenIn);
    }

    /**
     * @notice trigger an order to swap tokens and send them to the outputAccount
     * @dev it will swap up to the maximum amount allowed by the MocSwapper,
     *  or the contract’s full balance if it is lower
     */
    function triggerOrders() external nonReentrant {
        IMocSwapper _mocSwapper = mocSwapper;
        address _outputAccount = outputAccount;

        address _tokenIn = tokenIn;
        address _tokenOut = tokenOut;

        (uint256 amountIn, uint256 amountOutMin) = _getAmountOutMin();
        uint256 amountOut;

        if (_tokenIn == COINBASE) {
            amountOut = _mocSwapper.swapCoinbase{ value: amountIn }(_tokenOut, amountOutMin, _outputAccount);
        } else {
            SafeERC20.forceApprove(IERC20(_tokenIn), address(_mocSwapper), amountIn);
            amountOut = _mocSwapper.swapRC20(_tokenIn, _tokenOut, amountIn, amountOutMin, _outputAccount);
        }
        emit Triggered(_tokenIn, _tokenOut, amountIn, amountOut, _outputAccount);
    }

    /**
     * @notice Returns `true` if there is enough tokenIn to justify exchange orders
     * @dev triggerOrders should only be called when this function returns true but it is not enforced
     **/
    function readyToTriggerOrders() external view returns (bool) {
        return (_balanceOfSelf(tokenIn) >= orderThreshold);
    }

    /**
     * @notice returns the amountIn and amountOutMin for a swap
     * @return amountIn amount of tokenIn to swap
     * @return amountOutMin minimum amount of tokenOut expected
     */
    function getAmountOutMin() external view returns (uint256 amountIn, uint256 amountOutMin) {
        return _getAmountOutMin();
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @notice withdraws the entire balance of the contract to the given address
     * @dev only the authorized changer can call this function
     * @param token_ address of the token to be withdrawn
     * @param to_ address of the recipient
     */
    function emergencyWithdraw(address token_, address to_) external onlyAuthorizedChanger {
        uint256 balance = _balanceOfSelf(token_);
        _transfer(token_, to_, balance);
        emit EmergencyWithdraw(token_, to_, balance);
    }

    /**
     * @notice sets a new MocSwapper
     * @dev only the authorized changer can call this function
     * @param mocSwapper_ address of the MocSwapper contract
     */
    function setMocSwapper(address mocSwapper_) external onlyAuthorizedChanger {
        mocSwapper = IMocSwapper(mocSwapper_);
    }

    /**
     * @notice sets a new tokenIn
     * @dev only the authorized changer can call this function
     * @param tokenIn_ address of the token
     */
    function setTokenIn(address tokenIn_) external onlyAuthorizedChanger {
        tokenIn = tokenIn_;
    }

    /**
     * @notice sets a new tokenOut
     * @dev only the authorized changer can call this function
     * @param tokenOut_ address of the token
     */
    function setTokenOut(address tokenOut_) external onlyAuthorizedChanger {
        tokenOut = tokenOut_;
    }

    /**
     * @notice sets a new outputAccount
     * @dev only the authorized changer can call this function
     * @param outputAccount_ address of the output account
     */
    function setOutputAccount(address outputAccount_) external onlyAuthorizedChanger {
        outputAccount = outputAccount_;
    }

    /**
     * @notice sets a new orderThreshold
     * @dev only the authorized changer can call this function
     * @param orderThreshold_ new minimum amount of tokenIn that justifies trigger exchange orders
     */
    function setOrderThreshold(uint256 orderThreshold_) external onlyAuthorizedChanger {
        orderThreshold = orderThreshold_;
    }

    /**
     * @notice sets a new price provider
     * @dev only the authorized changer can call this function
     * @param priceProvider_ address of the price provider
     */
    function setPriceProvider(address priceProvider_) external onlyAuthorizedChanger {
        priceProvider = IPriceProvider(priceProvider_);
    }

    /**
     * @notice sets a new slippage value
     * @dev only the authorized changer can call this function
     * @param slippage_ new slippage value, 0.05 * 1e18 means 5%
     */
    function setSlippage(uint256 slippage_) external onlyAuthorizedChanger {
        _setSlippage(slippage_);
    }

    function _setSlippage(uint256 slippage_) internal {
        if (slippage_ > PRECISION) revert InvalidSlippage();
        slippage = slippage_;
    }

    function _getAmountOutMin() internal view returns (uint256 amountIn, uint256 amountOutMin) {
        IPriceProvider _priceProvider = priceProvider;
        (bytes32 price, ) = _priceProvider.peek();

        address _tokenIn = tokenIn;
        address _tokenOut = tokenOut;
        uint256 maxAmountToSwap = mocSwapper.getSafeMaxAmountToSwap(_tokenIn, _tokenOut);
        amountIn = Math.min(maxAmountToSwap, _balanceOfSelf(_tokenIn));
        amountOutMin = (amountIn * uint256(price)) / PRECISION;
        amountOutMin = (amountOutMin * (PRECISION - slippage)) / PRECISION;
    }

    // @notice used to receive coinbase
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {
        if (tokenIn != COINBASE) revert NotCoinbase();
    }
}
