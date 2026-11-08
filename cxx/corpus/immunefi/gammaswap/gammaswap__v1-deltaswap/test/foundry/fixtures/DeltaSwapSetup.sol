// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "../../../contracts/DeltaSwapRouter02.sol";
import "../../../contracts/DeltaSwapFactory.sol";

import "../../../contracts/test/WETH9.sol";
import "../../../contracts/test/ERC20Test.sol";

contract DeltaSwapSetup is Test {

    IDeltaSwapFactory public dsFactory;
    IDeltaSwapRouter02 public dsRouter;
    IDeltaSwapPair public dsPair;

    function initDeltaSwap(address owner, address weth, address usdc, address wbtc) public {
        // Let's do the same thing with `getCode`
        //bytes memory args = abi.encode(arg1, arg2);

        bytes memory gsFactoryArgs = abi.encode(owner);
        bytes memory gsFactoryBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/GammaPoolFactory.json"), gsFactoryArgs);
        address gsFactoryAddress;
        assembly {
            gsFactoryAddress := create(0, add(gsFactoryBytecode, 0x20), mload(gsFactoryBytecode))
        }

        dsFactory = new DeltaSwapFactory(owner, owner, gsFactoryAddress);
        dsRouter = new DeltaSwapRouter02(address(dsFactory), weth);

        dsPair = DeltaSwapPair(createPair(address(usdc), address(wbtc)));
        /*bytes memory bytecode = type(DeltaSwapPair).creationCode;
        bytes32 initCode = keccak256(bytecode);
        console.log("initCode");
        console.logBytes32(initCode);
        console.log("dsPair");
        console.log(address(dsPair));/**/
    }

    function createPair(address token0, address token1) public returns(address) {
        return dsFactory.createPair(token0, token1);
    }

    function addLiquidity(address token0, address token1, uint256 amount0, uint256 amount1, address to) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB, liquidity) = dsRouter.addLiquidity(token0, token1, amount0, amount1, 0, 0, to, type(uint256).max);
    }

    function removeLiquidity(address token0, address token1, uint256 liquidity) public returns (uint256 amount0, uint256 amount1) {
        return dsRouter.removeLiquidity(token0, token1, liquidity, 0, 0, msg.sender, type(uint256).max);
    }

    function buyTokenOut(uint256 amountOut, address tokenIn, address tokenOut) public returns(uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return dsRouter.swapTokensForExactTokens(amountOut, type(uint256).max, path, msg.sender, type(uint256).max);
    }

    function sellTokenIn(uint256 amountIn, address tokenIn, address tokenOut, address to) public returns(uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return dsRouter.swapExactTokensForTokens(amountIn, 0, path, to, type(uint256).max);
    }

    function approveRouter(address[] memory _addresses, address[] memory _tokens) public {
        for(uint256 i = 0; i < _addresses.length;i++) {
            approveRouterForAddress(_addresses[i], _tokens);
        }
    }

    function approveRouterForAddress(address _address, address[] memory _tokens) public {
        vm.startPrank(_address);
        for(uint256 j = 0; j < _tokens.length;j++) {
            IERC20Test(_tokens[j]).approve(address(dsRouter), type(uint256).max);
        }
        dsPair.approve(address(dsRouter), type(uint256).max);
        vm.stopPrank();
    }
}
