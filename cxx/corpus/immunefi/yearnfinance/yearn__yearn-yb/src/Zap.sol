// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICurvePool } from "src/interfaces/curve/ICurvePool.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IYToken } from "src/interfaces/IYToken.sol";
import { IYBS } from "src/interfaces/ybs/IYBS.sol";
import { IYBVotingEscrow } from "src/interfaces/yb/IYBVotingEscrow.sol";
import { IV2Vault } from "src/interfaces/yearn/IV2Vault.sol";
import { YV2Helper } from "src/utils/YearnV2Helper.sol";

/**
 * @title Zap
 * @notice Enables multi-step token conversions into and within the yYB ecosystem in a single transaction
 */
contract Zap {
    using SafeERC20 for IERC20;

    string public constant name = "Zap: yYB";

    address public immutable YB;
    address public immutable YYB;
    address public immutable YV_YYB;
    address public immutable LP_YYB;
    address public immutable YBS;
    address public immutable POOL;
    address public immutable VE_YB;
    uint256 public mintBuffer;

    event UpdateSweepRecipient(address indexed sweepRecipient);
    event UpdateMintBuffer(uint256 mintBuffer);

    modifier onlyOwner() {
        require(msg.sender == owner(), "!owner");
        _;
    }

    constructor(
        address _yb,
        address _yyb,
        address _stYyb,
        address _lpYyb,
        address _ybs,
        address _pool,
        address _veYb
    ) {
        require(_yb != address(0), "!yb");
        require(_yyb != address(0), "!yyb");
        require(_stYyb != address(0), "!stYyb");
        require(_lpYyb != address(0), "!lpYyb");
        require(_ybs != address(0), "!ybs");
        require(_pool != address(0), "!pool");
        require(_veYb != address(0), "!veYb");

        YB = _yb;
        YYB = _yyb;
        YV_YYB = _stYyb;
        LP_YYB = _lpYyb;
        YBS = _ybs;
        POOL = _pool;
        VE_YB = _veYb;
        mintBuffer = 15;

        IERC20(_yb).forceApprove(_yyb, type(uint256).max);
        IERC20(_yb).forceApprove(_pool, type(uint256).max);
        IERC20(_yyb).forceApprove(_pool, type(uint256).max);
        IERC20(_yyb).forceApprove(_stYyb, type(uint256).max);
        IERC20(_yyb).forceApprove(_ybs, type(uint256).max);
        IERC20(_pool).forceApprove(_lpYyb, type(uint256).max);
    }

    /**
     * @notice Zap from one yYB ecosystem token to another
     * @param inputToken Token to convert from
     * @param outputToken Token to convert to
     * @param amountIn Amount of input token (max uint256 for full balance)
     * @param minOut Minimum output amount (slippage protection)
     * @param recipient Address to receive output tokens
     * @return Amount of output tokens received
     * @dev When using YBS as input, caller must have previously called `YBS.setApprovedCaller()` 
     *  to allow this contract to manage their position.
     */
    function zap(
        address inputToken,
        address outputToken,
        uint256 amountIn,
        uint256 minOut,
        address recipient
    ) external returns (uint256) {
        require(isValidInputToken(inputToken), "invalid input token");
        require(isValidOutputToken(outputToken), "invalid output token");
        require(inputToken != outputToken, "same token");

        uint256 amount = amountIn;
        if (amount == type(uint256).max) {
            if (inputToken == VE_YB) {
                amount = _getLockedAmount(msg.sender);
            } else {
                amount = IERC20(inputToken).balanceOf(msg.sender);
            }
        }
        require(amount > 0, "!amount");
        uint256 yybAmount;

        if (inputToken == YB) {
            IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amount);
            yybAmount = _convertYb(amount);
        } else {
            if (inputToken != YBS) {
                if (inputToken == VE_YB) {
                    amount = _getLockedAmount(msg.sender);
                    require(amountIn >= amount, "lock > amountIn");
                    IERC721(VE_YB).safeTransferFrom(
                        msg.sender,
                        IYToken(YYB).locker(),
                        uint256(uint160(msg.sender)),
                        abi.encode(address(this)) // data
                    );
                } else {
                    IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amount);
                }
            }
            if (inputToken == YV_YYB) {
                yybAmount = IERC4626(YV_YYB).redeem(amount, address(this), address(this));
            } else if (inputToken == LP_YYB) {
                uint256 lpAmount = IV2Vault(LP_YYB).withdraw(amount, address(this));
                yybAmount = ICurvePool(POOL).remove_liquidity_one_coin(lpAmount, int128(1), 0, address(this));
            } else if (inputToken == YBS) {
                yybAmount = IYBS(YBS).unstakeFor(msg.sender, amount, address(this));
            }
            else yybAmount = amount;
        }

        if (outputToken == YYB) {
            require(yybAmount >= minOut, "slippage");
            IERC20(YYB).safeTransfer(recipient, yybAmount);
            return yybAmount;
        }

        return _convertToOutput(outputToken, yybAmount, minOut, recipient);
    }

    /**
     * @notice Convert YB to yYB via pool swap or direct mint
     * @dev Chooses most efficient path based on pool liquidity
     * @param amount Amount of YB to convert
     * @return Amount of yYB received
     */
    function _convertYb(uint256 amount) internal returns (uint256) {
        uint256 outputAmount = ICurvePool(POOL).get_dy(0, 1, amount);
        uint256 bufferedAmount = amount + (amount * mintBuffer / 10_000);

        if (outputAmount > bufferedAmount) {
            return ICurvePool(POOL).exchange(0, 1, amount, 0);
        } else {
            IYToken(YYB).mint(amount, address(this));
            return amount;
        }
    }

    /**
     * @notice Add liquidity to pool
     * @param _amounts array of amounts to deposit
     * @return LP tokens received
     */
    function _addLiquidity(uint256[] memory _amounts) internal returns (uint256) {
        return ICurvePool(POOL).add_liquidity(_amounts, 0, address(this));
    }

    

    /**
     * @notice Convert yYB to output token
     * @param outputToken Target output token
     * @param amount Amount of yYB to convert
     * @param minOut Minimum output amount
     * @param recipient Address to receive tokens
     * @return Amount of output tokens received
     */
    function _convertToOutput(
        address outputToken,
        uint256 amount,
        uint256 minOut,
        address recipient
    ) internal returns (uint256) {
        uint256 amountOut;

        if (outputToken == YV_YYB) {
            amountOut = IERC4626(YV_YYB).deposit(amount, recipient);
        } else if (outputToken == YBS) {
            amountOut = IYBS(YBS).stakeFor(recipient, amount);
            require(amountOut + 1 >= minOut, "slippage");
            return amountOut;
        } else {
            require(outputToken == LP_YYB, "unexpected output token");
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 0;
            amounts[1] = amount;
            uint256 lpTokens = _addLiquidity(amounts);
            amountOut = IV2Vault(LP_YYB).deposit(lpTokens, recipient);
        }

        require(amountOut >= minOut, "slippage");
        return amountOut;
    }

    /**
     * @notice Calculate expected output for a zap operation
     * @dev This function is for off-chain use only. It is subject to manipulation if used on chain.
     * @param inputToken Token to convert from
     * @param outputToken Token to convert to
     * @param amountIn Amount of input token
     * @return Expected output amount (accounting for slippage, not fees)
     */
    function calcExpectedOut(
        address inputToken,
        address outputToken,
        uint256 amountIn
    ) external view returns (uint256) {
        require(isValidInputToken(inputToken), "invalid input token");
        require(isValidOutputToken(outputToken), "invalid output token");
        require(inputToken != outputToken, "same token");

        if (amountIn == 0) {
            return 0;
        }

        uint256 amount = amountIn;

        if (inputToken == YB) {
            uint256 outputAmount = ICurvePool(POOL).get_dy(0, 1, amount);
            uint256 bufferedAmount = amount + (amount * mintBuffer / 10_000);
            amount = outputAmount > bufferedAmount ? outputAmount : amount;
        }
        else {
            if (inputToken == YV_YYB) {
                amount = IERC4626(YV_YYB).convertToAssets(amount);
            } else if (inputToken == LP_YYB) {
                uint256 lpAmount = YV2Helper.sharesToAmount(LP_YYB, amount);
                amount = ICurvePool(POOL).calc_withdraw_one_coin(lpAmount, int128(1));
            }
        }

        if (outputToken == YYB || outputToken == YBS) {
            return amount;
        } else if (outputToken == YV_YYB) {
            return IERC4626(YV_YYB).convertToShares(amount);
        } else {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 0;
            amounts[1] = amount;
            uint256 lpAmount = ICurvePool(POOL).calc_token_amount(amounts, true);
            return YV2Helper.amountToShares(LP_YYB, lpAmount);
        }
    }

    /**
     * @notice Calculate relative price between tokens (no slippage)
     * @dev Used to compare against calcExpectedOut to assess price impact
     * @param inputToken Token to convert from
     * @param outputToken Token to convert to
     * @param amountIn Amount of input token
     * @return Relative price in output token terms
     */
    function relativePrice(
        address inputToken,
        address outputToken,
        uint256 amountIn
    ) external view returns (uint256) {
        require(isValidOutputToken(outputToken), "invalid output token");
        require(isValidInputToken(inputToken), "invalid input token");

        if (amountIn == 0 || inputToken == outputToken) {
            return amountIn;
        }
        uint256 amount = amountIn;

        if (inputToken == YV_YYB) {
            amount = IERC4626(YV_YYB).convertToAssets(amount);
        } else if (inputToken == LP_YYB) {
            uint256 lpAmount = YV2Helper.sharesToAmount(LP_YYB, amount);
            amount = ICurvePool(POOL).get_virtual_price() * lpAmount / 1e18;
        }

        if (outputToken == YYB || outputToken == YBS) {
            return amount;
        } else if (outputToken == YV_YYB) {
            return IERC4626(YV_YYB).convertToShares(amount);
        } else {
            uint256 lpAmount = amount * 1e18 / ICurvePool(POOL).get_virtual_price();
            return YV2Helper.amountToShares(LP_YYB, lpAmount);
        }
    }

    /**
     * @notice Update mint buffer for YB->yYB conversion logic
     * @param newBuffer New buffer in basis points (max 500 = 5%)
     */
    function setMintBuffer(uint256 newBuffer) external onlyOwner {
        require(newBuffer < 500, "buffer too high");
        mintBuffer = newBuffer;
        emit UpdateMintBuffer(newBuffer);
    }

    /**
     * @notice Sweep tokens from contract
     * @param token Token to sweep
     * @param amount Amount to sweep (max uint256 for full balance)
     */
    function sweep(address token, uint256 amount) external onlyOwner {
        uint256 value = amount;
        if (value == type(uint256).max) {
            value = IERC20(token).balanceOf(address(this));
        }
        IERC20(token).safeTransfer(owner(), value);
    }

    // Input/Output Token Helpers
    function inputTokens() external view returns (address[] memory tokens) {
        tokens = new address[](6);
        tokens[0] = YB;
        tokens[1] = YYB;
        tokens[2] = YV_YYB;
        tokens[3] = LP_YYB;
        tokens[4] = YBS;
        tokens[5] = VE_YB;
        return tokens;
    }

    function outputTokens() external view returns (address[] memory tokens) {
        tokens = new address[](4);
        tokens[0] = YYB;
        tokens[1] = YV_YYB;
        tokens[2] = LP_YYB;
        tokens[3] = YBS;
        return tokens;
    }

    function isValidInputToken(address token) public view returns (bool) {
        return (
            token == YB ||
            token == YYB ||
            token == YV_YYB ||
            token == LP_YYB ||
            token == YBS ||
            token == VE_YB
        );
    }

    function isValidOutputToken(address token) public view returns (bool) {
        return (
            token == YYB ||
            token == YV_YYB ||
            token == LP_YYB ||
            token == YBS
        );
    }

    // Get locked YB for a user
    function _getLockedAmount(address user) internal view returns (uint256) {
        (int256 locked,) = IYBVotingEscrow(VE_YB).locked(user);
        return locked > 0 ? uint256(locked) : 0;
    }

    function owner() public view returns (address) {
        return IYToken(YYB).owner();
    }
}
