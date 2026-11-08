// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@gammaswap/v1-core/contracts/GammaPoolFactory.sol";
import "@gammaswap/v1-core/contracts/base/PoolViewer.sol";
import "@gammaswap/v1-implementations/contracts/pools/CPMMGammaPool.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/lending/CPMMBorrowStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/lending/CPMMRepayStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/rebalance/CPMMRebalanceStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMBatchLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/CPMMShortStrategy.sol";
import "@gammaswap/v1-implementations/contracts/libraries/cpmm/CPMMMath.sol";
import "@gammaswap/v1-periphery/contracts/PositionManagerWithStaking.sol";

import "./UniswapSetup.sol";
import "./RouterSetup.sol";

contract CPMMGammaSwapSetup is UniswapSetup, RouterSetup {
    GammaPoolFactory public factory;
    PositionManagerWithStaking public manager;

    CPMMBorrowStrategy public longStrategy;
    CPMMRepayStrategy public repayStrategy;
    CPMMRebalanceStrategy public rebalanceStrategy;
    CPMMShortStrategy public shortStrategy;
    CPMMLiquidationStrategy public liquidationStrategy;
    CPMMBatchLiquidationStrategy public batchLiquidationStrategy;
    CPMMGammaPool public protocol;
    CPMMGammaPool public pool;
    CPMMGammaPool public pool2;
    IPoolViewer public viewer;

    CPMMMath public mathLib;

    address public cfmm;
    address public cfmm2;
    address public owner;

    address user1;
    address user2;

    function initCPMMGammaSwap() public {
        owner = address(this);
        user1 = vm.addr(5);
        user2 = vm.addr(6);

        createTokens();
        mintTokens(user1, 4 * 1e24);
        mintTokens(user2, 4 * 1e24);

        //////// BEGIN: GammaSwap Core setup ////////
        initUniswap(owner, address(weth));
        approveUniRouter();

        factory = new GammaPoolFactory(owner);

        uint16 PROTOCOL_ID = 1;
        uint64 baseRate = 1e16;
        uint64 optimalUtilRate = 8 * 1e17;
        uint64 slope1 = 5 * 1e16;
        uint64 slope2 = 75 * 1e16;
        uint256 maxTotalApy = 1e19;

        mathLib = new CPMMMath();
        viewer = new PoolViewer();
        longStrategy = new CPMMBorrowStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, address(0), baseRate, optimalUtilRate, slope1, slope2);
        repayStrategy = new CPMMRepayStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, address(0), baseRate, optimalUtilRate, slope1, slope2);
        rebalanceStrategy = new CPMMRebalanceStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, address(0), baseRate, optimalUtilRate, slope1, slope2);
        shortStrategy = new CPMMShortStrategy(maxTotalApy, 2252571, baseRate, optimalUtilRate, slope1, slope2);
        liquidationStrategy = new CPMMLiquidationStrategy(address(0), address(mathLib), maxTotalApy, 2252571, 997, 1000, address(0), baseRate, optimalUtilRate, slope1, slope2);
        batchLiquidationStrategy = new CPMMBatchLiquidationStrategy(address(0), address(mathLib), maxTotalApy, 2252571, 997, 1000, address(0), baseRate, optimalUtilRate, slope1, slope2);

        bytes32 cfmmHash = hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f'; // UniV2Pair init_code_hash
        ICPMMGammaPool.InitializationParams memory params = ICPMMGammaPool.InitializationParams({
            protocolId: PROTOCOL_ID,
            factory: address(factory),
            borrowStrategy: address(longStrategy),
            repayStrategy: address(repayStrategy),
            rebalanceStrategy: address(rebalanceStrategy),
            shortStrategy: address(shortStrategy),
            liquidationStrategy: address(liquidationStrategy),
            batchLiquidationStrategy: address(batchLiquidationStrategy),
            viewer: address(viewer),
            externalRebalanceStrategy: address(0),
            externalLiquidationStrategy: address(0),
            cfmmFactory: address(uniFactory),
            cfmmInitCodeHash: cfmmHash
        });
        protocol = new CPMMGammaPool(params);

        factory.addProtocol(address(protocol));

        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);

        cfmm = createPair(tokens[0], tokens[1]);
        pool = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm, tokens, new bytes(0)));
        setPoolParams(address(pool), 0, 0, 10, 100, 100, 1, 250, 200, 1e11);// setting origination fees to zero
        approvePool(address(pool), address(cfmm));

        tokens[0] = address(weth);
        tokens[1] = address(usdt);

        cfmm2 = createPair(tokens[0], tokens[1]);
        pool2 = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm2, tokens, new bytes(0)));
        setPoolParams(address(pool2), 0, 0, 10, 100, 100, 1, 250, 200, 1e11);// setting origination fees to zero
        approvePool(address(pool2), address(cfmm2));

        //////// END: GammaSwap Core setup ////////

        //////// START: PositionManager ////////
        manager = new PositionManagerWithStaking(address(factory), address(weth));
        // bytes memory managerBytecode = abi.encodePacked(vm.getCode("./node_modules/@gammaswap/v1-periphery/artifacts/contracts/PositionManager.sol/PositionManager.json"), managerArgs);
        // assembly {
        //     sstore(manager.slot, create(0, add(managerBytecode, 0x20), mload(managerBytecode)))
        // }
        //////// END: PositionManager ////////

        //////// START: Staking ////////
        setupRouter(address(factory), address(manager), address(pool), address(pool2));
        manager.setStakingRouter(address(stakingRouter));
        //////// END: Staking ////////
    }

    function setPoolParams(address pool, uint16 origFee, uint8 extSwapFee, uint8 emaMultiplier, uint8 minUtilRate1, uint8 minUtilRate2,
        uint16 feeDivisor, uint8 liquidationFee, uint8 ltvThreshold, uint72 minBorrow) internal {
        vm.startPrank(address(factory));
        IGammaPool(pool).setPoolParams(origFee, extSwapFee, emaMultiplier, minUtilRate1, minUtilRate2, feeDivisor, liquidationFee, ltvThreshold, minBorrow);// setting origination fees to zero
        vm.stopPrank();
    }

    function approveUniRouter() public {
        vm.startPrank(user1);
        usdc.approve(address(uniRouter), type(uint256).max);
        usdt.approve(address(uniRouter), type(uint256).max);
        weth.approve(address(uniRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(uniRouter), type(uint256).max);
        usdt.approve(address(uniRouter), type(uint256).max);
        weth.approve(address(uniRouter), type(uint256).max);
        vm.stopPrank();
    }

    function approvePool(address _pool, address _cfmm) public {
        vm.startPrank(user1);
        IERC20(_pool).approve(address(_pool), type(uint256).max);
        IERC20(_cfmm).approve(address(_pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(_pool).approve(address(_pool), type(uint256).max);
        IERC20(_cfmm).approve(address(_pool), type(uint256).max);
        vm.stopPrank();
    }

    function depositLiquidityInPool(address addr, address _cfmm, address _pool) public {
        vm.startPrank(addr);
        uint256 lpTokens = IERC20(_cfmm).balanceOf(addr);
        CPMMGammaPool(_pool).deposit(lpTokens, addr);
        vm.stopPrank();
    }
    function depositLiquidityInCFMM(address addr, address _token0, address _token1, uint256 _amount0, uint256 _amount1) public {
        vm.startPrank(addr);
        addLiquidity(_token0, _token1, _amount0, _amount1, addr); // 1 weth = 1,000 USDC
        vm.stopPrank();
    }
}
