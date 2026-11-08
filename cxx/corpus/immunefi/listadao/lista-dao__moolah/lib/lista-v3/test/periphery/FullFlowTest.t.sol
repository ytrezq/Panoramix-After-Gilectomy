// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import 'forge-std/Test.sol';

import {ListaV3Pool} from '../../src/core/ListaV3Pool.sol';
import {ListaV3Factory} from '../../src/core/ListaV3Factory.sol';
import {IListaV3Pool} from '../../src/core/interfaces/IListaV3Pool.sol';
import {IListaV3PoolDeployer} from '../../src/core/interfaces/IListaV3PoolDeployer.sol';

import {NonfungiblePositionManager} from '../../src/periphery/NonfungiblePositionManager.sol';
import {SwapRouter} from '../../src/periphery/SwapRouter.sol';
import {INonfungiblePositionManager} from '../../src/periphery/interfaces/INonfungiblePositionManager.sol';
import {ISwapRouter} from '../../src/periphery/interfaces/ISwapRouter.sol';
import {PoolAddress} from '../../src/periphery/libraries/PoolAddress.sol';
import {ChainId} from '../../src/periphery/libraries/ChainId.sol';

import {TransparentUpgradeableProxy} from 'lib/openzeppelin-contracts/contracts/proxy/TransparentUpgradeableProxy.sol';
import {ProxyAdmin} from 'lib/openzeppelin-contracts/contracts/proxy/ProxyAdmin.sol';

import {TestERC20} from '../core/TestERC20.sol';

contract WETH9Mock {
    string public constant name = 'Wrapped Ether';
    string public constant symbol = 'WETH';
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Approval(address indexed src, address indexed guy, uint256 wad);

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        msg.sender.transfer(wad);
    }

    function totalSupply() external view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) external returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad);
        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        emit Transfer(src, dst, wad);
        return true;
    }
}

contract FullFlowTest is Test {
    ListaV3Factory internal factory;
    WETH9Mock internal weth;
    NonfungiblePositionManager internal npm;
    SwapRouter internal router;
    ProxyAdmin internal proxyAdmin;
    TestERC20 internal token0;
    TestERC20 internal token1;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint24 internal constant FEE = 3000;
    uint160 internal constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // 1:1
    int24 internal constant TICK_LOWER = -887220; // MIN_TICK rounded to spacing 60
    int24 internal constant TICK_UPPER = 887220;  // MAX_TICK rounded to spacing 60

    uint256 internal tokenId;
    uint128 internal mintedLiquidity;

    function setUp() public {
        weth = new WETH9Mock();
        proxyAdmin = new ProxyAdmin();

        factory = new ListaV3Factory();

        NonfungiblePositionManager npmImpl = new NonfungiblePositionManager(address(factory), address(weth));
        bytes memory npmInit = abi.encodeWithSelector(NonfungiblePositionManager.initialize.selector, address(0));
        TransparentUpgradeableProxy npmProxy =
            new TransparentUpgradeableProxy(address(npmImpl), address(proxyAdmin), npmInit);
        npm = NonfungiblePositionManager(payable(address(npmProxy)));

        router = new SwapRouter(address(factory), address(weth));

        TestERC20 a = new TestERC20(type(uint128).max);
        TestERC20 b = new TestERC20(type(uint128).max);
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);

        token0.transfer(alice, 1e24);
        token1.transfer(alice, 1e24);

        vm.startPrank(alice);
        token0.approve(address(npm), type(uint256).max);
        token1.approve(address(npm), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.label(alice, 'alice');
        vm.label(bob, 'bob');
    }

    /// @notice Sanity check: the hardcoded POOL_INIT_CODE_HASH in PoolAddress must match
    /// the actual compiled pool creation code. If this fails after a rename, update the
    /// constant in src/periphery/libraries/PoolAddress.sol with the computed value.
    function testInitCodeHash() public {
        bytes32 actual = keccak256(type(ListaV3Pool).creationCode);
        assertEq(actual, PoolAddress.POOL_INIT_CODE_HASH);
    }

    /// @notice Verifies NPM's constructor-set immutables and initializer-set state on the proxy.
    function testNpmImmutablesAndInitialState() public {
        // Immutables baked into the impl via PeripheryImmutableState(ctor) — resolve through delegatecall
        assertEq(npm.factory(), address(factory));
        assertEq(npm.WETH9(), address(weth));

        // ERC721 metadata set by __ERC721_init through initialize()
        assertEq(npm.name(), 'Lista V3 Positions NFT-V1');
        assertEq(npm.symbol(), 'LIS-V3-POS');

        // EIP-165 registrations written to proxy storage during initialize()
        assertTrue(npm.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(npm.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(npm.supportsInterface(0x5b5e139f)); // ERC721Metadata
        assertTrue(npm.supportsInterface(0x780e9d63)); // ERC721Enumerable
        assertFalse(npm.supportsInterface(0xffffffff));

        // ERC721Permit typehash is a compile-time constant; DOMAIN_SEPARATOR is bound to the proxy
        assertEq(
            npm.PERMIT_TYPEHASH(),
            0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad
        );
        bytes32 expectedDomain =
            keccak256(
                abi.encode(
                    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                    keccak256(bytes('Lista V3 Positions NFT-V1')),
                    keccak256(bytes('1')),
                    ChainId.get(),
                    address(npm)
                )
            );
        assertEq(npm.DOMAIN_SEPARATOR(), expectedDomain);

        // Enumerable baseline before any mint
        assertEq(npm.totalSupply(), 0);
        assertEq(npm.balanceOf(alice), 0);

        // Initializer is one-shot
        vm.expectRevert(bytes('Initializable: contract is already initialized'));
        npm.initialize(address(0));
    }

    function testFullFlow() public {
        _createPool();
        _mintPosition();
        _swap();
        _increaseLiquidity();
        _decreaseAndCollect();
        _transferAndBurn();
    }

    function _createPool() internal {
        address pool = npm.createAndInitializePoolIfNecessary(
            address(token0),
            address(token1),
            FEE,
            INITIAL_SQRT_PRICE
        );
        assertTrue(pool != address(0));

        // Deployer's transient parameters storage must be cleared after deploy
        IListaV3PoolDeployer deployer = IListaV3PoolDeployer(address(factory));
        (address pf, address pt0, address pt1, uint24 pfee, int24 pspacing) = deployer.parameters();
        assertEq(pf, address(0));
        assertEq(pt0, address(0));
        assertEq(pt1, address(0));
        assertEq(uint256(pfee), 0);
        assertEq(int256(pspacing), 0);

        // Pool immutables must match what the deployer supplied during construction
        IListaV3Pool p = IListaV3Pool(pool);
        assertEq(p.factory(), address(factory));
        assertEq(p.token0(), address(token0));
        assertEq(p.token1(), address(token1));
        assertEq(uint256(p.fee()), uint256(FEE));
        assertEq(int256(p.tickSpacing()), int256(factory.feeAmountTickSpacing(FEE)));
    }

    function _mintPosition() internal {
        vm.prank(alice);
        (uint256 _tokenId, uint128 _liquidity, uint256 a0, uint256 a1) = npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: 1e20,
                amount1Desired: 1e20,
                amount0Min: 0,
                amount1Min: 0,
                recipient: alice,
                deadline: block.timestamp + 1000
            })
        );
        tokenId = _tokenId;
        mintedLiquidity = _liquidity;
        // Verifies initialize() seeded _nextId = 1 (first mint must return tokenId 1)
        assertEq(tokenId, 1);
        assertEq(npm.totalSupply(), 1);
        assertEq(npm.balanceOf(alice), 1);
        assertEq(npm.ownerOf(tokenId), alice);
        assertTrue(_liquidity > 0);
        assertTrue(a0 > 0 && a1 > 0);
    }

    function _swap() internal {
        vm.prank(alice);
        uint256 amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: FEE,
                recipient: alice,
                deadline: block.timestamp + 1000,
                amountIn: 1e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        assertTrue(amountOut > 0);
    }

    function _increaseLiquidity() internal {
        vm.prank(alice);
        (uint128 added, , ) = npm.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: 1e18,
                amount1Desired: 1e18,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1000
            })
        );
        assertTrue(added > 0);
    }

    function _decreaseAndCollect() internal {
        vm.startPrank(alice);
        (uint256 dec0, uint256 dec1) = npm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: mintedLiquidity / 2,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1000
            })
        );
        assertTrue(dec0 > 0 || dec1 > 0);

        uint256 bal0Before = token0.balanceOf(alice);
        uint256 bal1Before = token1.balanceOf(alice);
        (uint256 col0, uint256 col1) = npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: alice,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        assertTrue(col0 > 0 || col1 > 0);
        assertEq(token0.balanceOf(alice), bal0Before + col0);
        assertEq(token1.balanceOf(alice), bal1Before + col1);
        vm.stopPrank();
    }

    function _transferAndBurn() internal {
        // Transfer NFT alice -> bob
        vm.prank(alice);
        npm.transferFrom(alice, bob, tokenId);
        assertEq(npm.ownerOf(tokenId), bob);

        // Bob clears out the position: decrease remaining liquidity, collect, burn
        (, , , , , , , uint128 remaining, , , , ) = npm.positions(tokenId);
        assertTrue(remaining > 0);

        vm.startPrank(bob);
        npm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: remaining,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1000
            })
        );
        (uint256 bCol0, uint256 bCol1) = npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: bob,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        assertTrue(bCol0 > 0 || bCol1 > 0);

        npm.burn(tokenId);

        vm.expectRevert();
        npm.ownerOf(tokenId);
        vm.stopPrank();
    }
}
