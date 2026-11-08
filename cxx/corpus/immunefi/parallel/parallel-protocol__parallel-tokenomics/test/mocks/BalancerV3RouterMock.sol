// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IBalancerV3Router } from "contracts/interfaces/IBalancerV3Router.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "./ERC20Mock.sol";
import { IPermit2 } from "contracts/interfaces/IPermit2.sol";

contract BalancerV3RouterMock is IBalancerV3Router {
    address[2] public tokens;
    ERC20Mock public bpt;
    IPermit2 public permit2;
    uint256 ratio = 1e18;

    constructor(address[2] memory _tokens, address _bpt, address _permit2) {
        tokens = _tokens;
        bpt = ERC20Mock(_bpt);
        permit2 = IPermit2(_permit2);
    }

    function updateRatio(uint256 _ratio) external {
        ratio = _ratio;
    }

    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    )
        external
        payable
        override
        returns (uint256[] memory amountsIn)
    {
        uint256 amountIn0 = (maxAmountsIn[0] * ratio) / 1e18;
        uint256 amountIn1 = (maxAmountsIn[1] * ratio) / 1e18;
        permit2.transferFrom(msg.sender, address(this), uint160(amountIn0), tokens[0]);
        permit2.transferFrom(msg.sender, address(this), uint160(amountIn1), tokens[1]);
        bpt.mint(msg.sender, exactBptAmountOut);
        amountsIn = new uint256[](2);
        amountsIn[0] = amountIn0;
        amountsIn[1] = amountIn1;
    }

    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    )
        external
        payable
        override
        returns (uint256[] memory amountsOut)
    {
        bpt.burn(msg.sender, exactBptAmountIn);
        IERC20(tokens[0]).transfer(msg.sender, minAmountsOut[0]);
        IERC20(tokens[1]).transfer(msg.sender, minAmountsOut[1]);
        return minAmountsOut;
    }

    function queryRemoveLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    )
        external
        returns (uint256[] memory amountsOut)
    { }
}
