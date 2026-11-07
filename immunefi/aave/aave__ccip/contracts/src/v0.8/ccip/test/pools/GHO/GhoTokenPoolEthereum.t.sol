// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {stdError} from "forge-std/Test.sol";
import {IERC165} from "../../../../vendor/openzeppelin-solidity/v4.8.3/contracts/utils/introspection/IERC165.sol";
import {ILiquidityContainer} from "../../../../liquiditymanager/interfaces/ILiquidityContainer.sol";
import {IPoolV1} from "../../../interfaces/IPool.sol";
import {Pool} from "../../../libraries/Pool.sol";
import {LockReleaseTokenPool} from "../../../pools/LockReleaseTokenPool.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {EVM2EVMOffRamp} from "../../../offRamp/EVM2EVMOffRamp.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";
import {MockUpgradeable} from "../../mocks/MockUpgradeable.sol";
import {GhoTokenPoolEthereumSetup} from "./GhoTokenPoolEthereumSetup.t.sol";

contract GhoTokenPoolEthereum_setRebalancer is GhoTokenPoolEthereumSetup {
  function testSetRebalancerSuccess() public {
    assertEq(address(s_ghoTokenPool.getRebalancer()), OWNER);
    changePrank(AAVE_DAO);
    s_ghoTokenPool.setRebalancer(STRANGER);
    assertEq(address(s_ghoTokenPool.getRebalancer()), STRANGER);
  }

  function testSetRebalancerReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert(OnlyCallableByOwner.selector);
    s_ghoTokenPool.setRebalancer(STRANGER);
  }
}

contract GhoTokenPoolEthereum_lockOrBurn is GhoTokenPoolEthereumSetup {
  error SenderNotAllowed(address sender);

  event Locked(address indexed sender, uint256 amount);
  event TokensConsumed(uint256 tokens);

  function testFuzz_LockOrBurnNoAllowListSuccess(uint256 amount, uint256 bridgedAmount) public {
    uint256 maxAmount = _getOutboundRateLimiterConfig().capacity < INITIAL_BRIDGE_LIMIT
      ? _getOutboundRateLimiterConfig().capacity
      : INITIAL_BRIDGE_LIMIT;
    amount = bound(amount, 1, maxAmount);
    bridgedAmount = bound(bridgedAmount, 0, INITIAL_BRIDGE_LIMIT - amount);

    changePrank(s_allowedOnRamp);
    if (bridgedAmount > 0) {
      s_ghoTokenPool.lockOrBurn(
        Pool.LockOrBurnInV1({
          receiver: bytes(""),
          remoteChainSelector: DEST_CHAIN_SELECTOR,
          originalSender: STRANGER,
          amount: bridgedAmount,
          localToken: address(s_token)
        })
      );
      assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), bridgedAmount);
    }

    vm.expectEmit();
    emit TokensConsumed(amount);
    vm.expectEmit();
    emit Locked(s_allowedOnRamp, amount);

    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: amount,
        localToken: address(s_token)
      })
    );

    assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), bridgedAmount + amount);
  }

  function testTokenMaxCapacityExceededReverts() public {
    RateLimiter.Config memory rateLimiterConfig = _getOutboundRateLimiterConfig();
    uint256 capacity = rateLimiterConfig.capacity;
    uint256 amount = 10 * capacity;

    // increase bridge limit to hit the rate limit error
    vm.startPrank(AAVE_DAO);
    s_ghoTokenPool.setBridgeLimit(amount);

    vm.expectRevert(
      abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_token))
    );
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: amount,
        localToken: address(s_token)
      })
    );
  }

  function testTokenBridgeLimitExceededReverts() public {
    uint256 bridgeLimit = s_ghoTokenPool.getBridgeLimit();
    uint256 amount = bridgeLimit + 1;

    vm.expectRevert(abi.encodeWithSelector(UpgradeableLockReleaseTokenPool.BridgeLimitExceeded.selector, bridgeLimit));
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: amount,
        localToken: address(s_token)
      })
    );
  }
}

contract GhoTokenPoolEthereum_releaseOrMint is GhoTokenPoolEthereumSetup {
  event TokensConsumed(uint256 tokens);
  event Released(address indexed sender, address indexed recipient, uint256 amount);
  event ChainRemoved(uint64 chainSelector);

  function setUp() public virtual override {
    GhoTokenPoolEthereumSetup.setUp();

    UpgradeableTokenPool.ChainUpdate[] memory chainUpdate = new UpgradeableTokenPool.ChainUpdate[](1);
    bytes[] memory remotePoolAddresses = new bytes[](1);
    remotePoolAddresses[0] = abi.encode(s_sourcePool);
    chainUpdate[0] = UpgradeableTokenPool.ChainUpdate({
      remoteChainSelector: SOURCE_CHAIN_SELECTOR,
      remotePoolAddresses: remotePoolAddresses,
      remoteTokenAddress: abi.encode(s_sourceToken),
      outboundRateLimiterConfig: _getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: _getInboundRateLimiterConfig()
    });

    changePrank(AAVE_DAO);
    s_ghoTokenPool.applyChainUpdates(new uint64[](0), chainUpdate);
  }

  function test_ReleaseOrMintSuccess() public {
    uint256 amount = 100;
    deal(address(s_token), address(s_ghoTokenPool), amount);

    // Inflate current bridged amount so it can be reduced in `releaseOrMint` function
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: amount,
        localToken: address(s_token)
      })
    );

    vm.expectEmit();
    emit TokensConsumed(amount);
    vm.expectEmit();
    emit Released(s_allowedOffRamp, OWNER, amount);

    vm.startPrank(s_allowedOffRamp);
    s_ghoTokenPool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        amount: amount,
        remoteChainSelector: SOURCE_CHAIN_SELECTOR,
        receiver: OWNER,
        localToken: address(s_token),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );

    assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), 0);
  }

  function testFuzz_ReleaseOrMintSuccess(address recipient, uint256 amount, uint256 bridgedAmount) public {
    // Since the owner already has tokens this would break the checks
    vm.assume(recipient != OWNER);
    vm.assume(recipient != address(0));
    vm.assume(recipient != address(s_token));

    amount = uint128(bound(amount, 2, type(uint128).max));
    bridgedAmount = uint128(bound(bridgedAmount, amount, type(uint128).max));

    // Inflate current bridged amount so it can be reduced in `releaseOrMint` function
    vm.startPrank(AAVE_DAO);
    s_ghoTokenPool.setBridgeLimit(bridgedAmount);
    s_ghoTokenPool.setChainRateLimiterConfig(
      DEST_CHAIN_SELECTOR,
      RateLimiter.Config({isEnabled: true, capacity: type(uint128).max, rate: 1e15}),
      RateLimiter.Config({isEnabled: true, capacity: type(uint128).max, rate: 1e15})
    );
    vm.warp(block.timestamp + 1e50); // wait to refill capacity
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: bridgedAmount,
        localToken: address(s_token)
      })
    );

    // Makes sure the pool always has enough funds
    deal(address(s_token), address(s_ghoTokenPool), amount);
    vm.startPrank(s_allowedOffRamp);

    uint256 capacity = _getInboundRateLimiterConfig().capacity;
    uint256 bridgedAmountAfter = bridgedAmount;
    // Determine if we hit the rate limit or the txs should succeed.
    if (amount > capacity) {
      vm.expectRevert(
        abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_token))
      );
    } else {
      // Only rate limit if the amount is >0
      if (amount > 0) {
        vm.expectEmit();
        emit TokensConsumed(amount);
      }

      vm.expectEmit();
      emit Released(s_allowedOffRamp, recipient, amount);

      bridgedAmountAfter -= amount;
    }

    s_ghoTokenPool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        amount: amount,
        remoteChainSelector: SOURCE_CHAIN_SELECTOR,
        receiver: recipient,
        localToken: address(s_token),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );

    assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), bridgedAmountAfter);
  }

  function testChainNotAllowedReverts() public {
    uint256 amount = 1e5;
    vm.startPrank(AAVE_DAO);
    // increase bridge amount which can later be offRamped
    s_ghoTokenPool.setCurrentBridgedAmount(amount);

    uint64[] memory remoteChainSelectorsToRemove = new uint64[](1);
    remoteChainSelectorsToRemove[0] = SOURCE_CHAIN_SELECTOR;
    vm.expectEmit(address(s_ghoTokenPool));
    emit ChainRemoved(SOURCE_CHAIN_SELECTOR);
    s_ghoTokenPool.applyChainUpdates(remoteChainSelectorsToRemove, new UpgradeableTokenPool.ChainUpdate[](0));

    vm.startPrank(s_allowedOffRamp);

    vm.expectRevert(abi.encodeWithSelector(UpgradeableTokenPool.ChainNotAllowed.selector, SOURCE_CHAIN_SELECTOR));
    s_ghoTokenPool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        amount: amount,
        remoteChainSelector: SOURCE_CHAIN_SELECTOR,
        receiver: OWNER,
        localToken: address(s_token),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
  }

  function testPoolMintNotHealthyReverts() public {
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: 1e5,
        localToken: address(s_token)
      })
    );

    // Should not mint tokens if cursed.
    s_mockRMN.setGlobalCursed(true);
    uint256 before = s_token.balanceOf(OWNER);
    vm.startPrank(s_allowedOffRamp);
    vm.expectRevert(EVM2EVMOffRamp.CursedByRMN.selector);
    s_ghoTokenPool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        amount: 1e5,
        remoteChainSelector: SOURCE_CHAIN_SELECTOR,
        receiver: OWNER,
        localToken: address(s_token),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
    assertEq(s_token.balanceOf(OWNER), before);
  }

  function testReleaseNoFundsReverts() public {
    uint256 amount = 1;

    // Inflate current bridged amount so it can be reduced in `releaseOrMint` function
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: amount,
        localToken: address(s_token)
      })
    );

    vm.expectRevert(stdError.arithmeticError);
    vm.startPrank(s_allowedOffRamp);
    s_ghoTokenPool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        amount: amount,
        remoteChainSelector: SOURCE_CHAIN_SELECTOR,
        receiver: STRANGER,
        localToken: address(s_token),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
  }

  function testTokenMaxCapacityExceededReverts() public {
    RateLimiter.Config memory rateLimiterConfig = _getInboundRateLimiterConfig();
    uint256 capacity = rateLimiterConfig.capacity;
    uint256 amount = 10 * capacity;

    // Inflate current bridged amount so it can be reduced in `releaseOrMint` function
    vm.startPrank(AAVE_DAO);
    s_ghoTokenPool.setBridgeLimit(amount);
    s_ghoTokenPool.setChainRateLimiterConfig(
      DEST_CHAIN_SELECTOR,
      RateLimiter.Config({isEnabled: true, capacity: type(uint128).max, rate: 1e15}),
      _getInboundRateLimiterConfig()
    );
    vm.warp(block.timestamp + 1e50); // wait to refill capacity
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: amount,
        localToken: address(s_token)
      })
    );

    vm.expectRevert(
      abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_token))
    );
    vm.startPrank(s_allowedOffRamp);
    s_ghoTokenPool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        amount: amount,
        remoteChainSelector: SOURCE_CHAIN_SELECTOR,
        receiver: STRANGER,
        localToken: address(s_token),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
  }

  function testBridgedAmountNotEnoughReverts() public {
    uint256 amount = 10;
    vm.expectRevert(abi.encodeWithSelector(UpgradeableLockReleaseTokenPool.NotEnoughBridgedAmount.selector));
    vm.startPrank(s_allowedOffRamp);
    s_ghoTokenPool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        amount: amount,
        remoteChainSelector: SOURCE_CHAIN_SELECTOR,
        receiver: STRANGER,
        localToken: address(s_token),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
  }
}

contract GhoTokenPoolEthereum_canAcceptLiquidity is GhoTokenPoolEthereumSetup {
  function test_CanAcceptLiquiditySuccess() public {
    assertEq(true, s_ghoTokenPool.canAcceptLiquidity());

    s_ghoTokenPool = new UpgradeableLockReleaseTokenPool(address(s_token), 18, address(s_mockRMN), false, false);

    assertEq(false, s_ghoTokenPool.canAcceptLiquidity());
  }
}

contract GhoTokenPoolEthereum_provideLiquidity is GhoTokenPoolEthereumSetup {
  function testFuzz_ProvideLiquiditySuccess(uint256 amount) public {
    vm.assume(amount < type(uint128).max);

    uint256 balancePre = s_token.balanceOf(OWNER);
    s_token.approve(address(s_ghoTokenPool), amount);

    s_ghoTokenPool.provideLiquidity(amount);

    assertEq(s_token.balanceOf(OWNER), balancePre - amount);
    assertEq(s_token.balanceOf(address(s_ghoTokenPool)), amount);
  }

  // Reverts

  function test_UnauthorizedReverts() public {
    vm.startPrank(STRANGER);
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, STRANGER));

    s_ghoTokenPool.provideLiquidity(1);
  }

  function testFuzz_ExceedsAllowance(uint256 amount) public {
    vm.assume(amount > 0);

    vm.expectRevert(stdError.arithmeticError);
    s_ghoTokenPool.provideLiquidity(amount);
  }

  function testLiquidityNotAcceptedReverts() public {
    s_ghoTokenPool = new UpgradeableLockReleaseTokenPool(address(s_token), 18, address(s_mockRMN), false, false);

    vm.expectRevert(LockReleaseTokenPool.LiquidityNotAccepted.selector);
    s_ghoTokenPool.provideLiquidity(1);
  }
}

contract GhoTokenPoolEthereum_withdrawalLiquidity is GhoTokenPoolEthereumSetup {
  function testFuzz_WithdrawalLiquiditySuccess(uint256 amount) public {
    vm.assume(amount < type(uint128).max);

    uint256 balancePre = s_token.balanceOf(OWNER);
    s_token.approve(address(s_ghoTokenPool), amount);
    s_ghoTokenPool.provideLiquidity(amount);

    s_ghoTokenPool.withdrawLiquidity(amount);

    assertEq(s_token.balanceOf(OWNER), balancePre);
  }

  // Reverts

  function test_UnauthorizedReverts() public {
    vm.startPrank(STRANGER);
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, STRANGER));

    s_ghoTokenPool.withdrawLiquidity(1);
  }

  function testInsufficientLiquidityReverts() public {
    uint256 maxUint128 = 2 ** 128 - 1;

    s_token.approve(address(s_ghoTokenPool), maxUint128);
    s_ghoTokenPool.provideLiquidity(maxUint128);

    changePrank(address(s_ghoTokenPool));
    s_token.transfer(OWNER, maxUint128);
    changePrank(OWNER);

    vm.expectRevert(LockReleaseTokenPool.InsufficientLiquidity.selector);
    s_ghoTokenPool.withdrawLiquidity(1);
  }
}

contract GhoTokenPoolEthereum_transferLiquidity is GhoTokenPoolEthereumSetup {
  UpgradeableLockReleaseTokenPool internal s_oldLockReleaseTokenPool;

  uint256 internal s_amount = 100_000_000e18;

  error BridgeLimitExceeded(uint256 limit);
  error InsufficientLiquidity();

  function setUp() public virtual override {
    super.setUp();

    s_oldLockReleaseTokenPool = UpgradeableLockReleaseTokenPool(
      _deployUpgradeableLockReleaseTokenPool(
        address(s_token),
        address(s_mockRMN),
        address(s_sourceRouter),
        AAVE_DAO,
        INITIAL_BRIDGE_LIMIT,
        PROXY_ADMIN
      )
    );
    deal(address(s_token), address(s_oldLockReleaseTokenPool), s_amount);
    changePrank(AAVE_DAO);
    s_oldLockReleaseTokenPool.setCurrentBridgedAmount(s_amount);
  }

  function testFuzz_TransferLiquidity(uint256 amount) public {
    amount = bound(amount, 1, s_amount);

    s_oldLockReleaseTokenPool.setRebalancer(address(s_ghoTokenPool));

    s_ghoTokenPool.transferLiquidity(address(s_oldLockReleaseTokenPool), amount);

    assertEq(s_token.balanceOf(address(s_ghoTokenPool)), amount);
    assertEq(s_token.balanceOf(address(s_oldLockReleaseTokenPool)), s_amount - amount);
  }

  // Reverts

  function test_UnauthorizedReverts() public {
    changePrank(STRANGER);
    vm.expectRevert(OnlyCallableByOwner.selector);

    s_ghoTokenPool.transferLiquidity(address(1), 1);
  }

  function testFuzz_RevertsTransferLiquidityExcess(uint256 amount) public {
    uint256 existingLiquidity = s_token.balanceOf(address(s_oldLockReleaseTokenPool));
    amount = bound(amount, existingLiquidity + 1, type(uint256).max);

    s_oldLockReleaseTokenPool.setRebalancer(address(s_ghoTokenPool));

    vm.expectRevert(InsufficientLiquidity.selector);
    s_ghoTokenPool.transferLiquidity(address(s_oldLockReleaseTokenPool), amount);
  }
}

contract GhoTokenPoolEthereum_setCurrentBridgedAmount is GhoTokenPoolEthereumSetup {
  function test_UnauthorizedReverts() public {
    changePrank(STRANGER);
    vm.expectRevert(OnlyCallableByOwner.selector);

    s_ghoTokenPool.setCurrentBridgedAmount(1);
  }

  function test_SetCurrentBridgedAmountAdminSuccess(uint256 amount) public {
    changePrank(AAVE_DAO);
    s_ghoTokenPool.setCurrentBridgedAmount(amount);

    assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), amount);
  }
}

contract GhoTokenPoolEthereum_supportsInterface is GhoTokenPoolEthereumSetup {
  function testSupportsInterfaceSuccess() public view {
    assertTrue(s_ghoTokenPool.supportsInterface(type(ILiquidityContainer).interfaceId));
    assertTrue(s_ghoTokenPool.supportsInterface(type(IPoolV1).interfaceId));
    assertTrue(s_ghoTokenPool.supportsInterface(type(IERC165).interfaceId));
  }
}

contract GhoTokenPoolEthereum_setChainRateLimiterConfig is GhoTokenPoolEthereumSetup {
  event ConfigChanged(RateLimiter.Config);
  event ChainConfigured(
    uint64 chainSelector,
    RateLimiter.Config outboundRateLimiterConfig,
    RateLimiter.Config inboundRateLimiterConfig
  );

  uint64 internal s_remoteChainSelector;

  function setUp() public virtual override {
    GhoTokenPoolEthereumSetup.setUp();
    UpgradeableTokenPool.ChainUpdate[] memory chainUpdates = new UpgradeableTokenPool.ChainUpdate[](1);
    s_remoteChainSelector = 123124;
    bytes[] memory remotePoolAddresses = new bytes[](1);
    remotePoolAddresses[0] = abi.encode(s_sourcePool);
    chainUpdates[0] = UpgradeableTokenPool.ChainUpdate({
      remoteChainSelector: s_remoteChainSelector,
      remotePoolAddresses: remotePoolAddresses,
      remoteTokenAddress: abi.encode(s_sourceToken),
      outboundRateLimiterConfig: _getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: _getInboundRateLimiterConfig()
    });
    changePrank(AAVE_DAO);
    s_ghoTokenPool.applyChainUpdates(new uint64[](0), chainUpdates);
    changePrank(OWNER);
  }

  function testFuzz_SetChainRateLimiterConfigSuccess(uint128 capacity, uint128 rate, uint32 newTime) public {
    // Cap the lower bound to 4 so 4/2 is still >= 2
    vm.assume(capacity >= 4);
    // Cap the lower bound to 2 so 2/2 is still >= 1
    rate = uint128(bound(rate, 2, capacity - 2));
    // Bucket updates only work on increasing time
    newTime = uint32(bound(newTime, block.timestamp + 1, type(uint32).max));
    vm.warp(newTime);

    uint256 oldOutboundTokens = s_ghoTokenPool.getCurrentOutboundRateLimiterState(s_remoteChainSelector).tokens;
    uint256 oldInboundTokens = s_ghoTokenPool.getCurrentInboundRateLimiterState(s_remoteChainSelector).tokens;

    RateLimiter.Config memory newOutboundConfig = RateLimiter.Config({isEnabled: true, capacity: capacity, rate: rate});
    RateLimiter.Config memory newInboundConfig = RateLimiter.Config({
      isEnabled: true,
      capacity: capacity / 2,
      rate: rate / 2
    });

    vm.expectEmit();
    emit ConfigChanged(newOutboundConfig);
    vm.expectEmit();
    emit ConfigChanged(newInboundConfig);
    vm.expectEmit();
    emit ChainConfigured(s_remoteChainSelector, newOutboundConfig, newInboundConfig);

    changePrank(AAVE_DAO);
    s_ghoTokenPool.setChainRateLimiterConfig(s_remoteChainSelector, newOutboundConfig, newInboundConfig);

    uint256 expectedTokens = RateLimiter._min(newOutboundConfig.capacity, oldOutboundTokens);

    RateLimiter.TokenBucket memory bucket = s_ghoTokenPool.getCurrentOutboundRateLimiterState(s_remoteChainSelector);
    assertEq(bucket.capacity, newOutboundConfig.capacity);
    assertEq(bucket.rate, newOutboundConfig.rate);
    assertEq(bucket.tokens, expectedTokens);
    assertEq(bucket.lastUpdated, newTime);

    expectedTokens = RateLimiter._min(newInboundConfig.capacity, oldInboundTokens);

    bucket = s_ghoTokenPool.getCurrentInboundRateLimiterState(s_remoteChainSelector);
    assertEq(bucket.capacity, newInboundConfig.capacity);
    assertEq(bucket.rate, newInboundConfig.rate);
    assertEq(bucket.tokens, expectedTokens);
    assertEq(bucket.lastUpdated, newTime);
  }

  function testOnlyOwnerOrRateLimitAdminSuccess() public {
    address rateLimiterAdmin = address(28973509103597907);

    changePrank(AAVE_DAO);
    s_ghoTokenPool.setRateLimitAdmin(rateLimiterAdmin);

    changePrank(rateLimiterAdmin);

    s_ghoTokenPool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      _getOutboundRateLimiterConfig(),
      _getInboundRateLimiterConfig()
    );

    changePrank(AAVE_DAO);

    s_ghoTokenPool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      _getOutboundRateLimiterConfig(),
      _getInboundRateLimiterConfig()
    );
  }

  // Reverts

  function testOnlyOwnerReverts() public {
    changePrank(STRANGER);

    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, STRANGER));
    s_ghoTokenPool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      _getOutboundRateLimiterConfig(),
      _getInboundRateLimiterConfig()
    );
  }

  function testNonExistentChainReverts() public {
    uint64 wrongChainSelector = 9084102894;

    vm.expectRevert(abi.encodeWithSelector(UpgradeableTokenPool.NonExistentChain.selector, wrongChainSelector));
    changePrank(AAVE_DAO);
    s_ghoTokenPool.setChainRateLimiterConfig(
      wrongChainSelector,
      _getOutboundRateLimiterConfig(),
      _getInboundRateLimiterConfig()
    );
  }
}

contract GhoTokenPoolEthereum_setRateLimitAdmin is GhoTokenPoolEthereumSetup {
  function testSetRateLimitAdminSuccess() public {
    assertEq(address(0), s_ghoTokenPool.getRateLimitAdmin());
    changePrank(AAVE_DAO);
    s_ghoTokenPool.setRateLimitAdmin(OWNER);
    assertEq(OWNER, s_ghoTokenPool.getRateLimitAdmin());
  }

  // Reverts

  function testSetRateLimitAdminReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert(OnlyCallableByOwner.selector);
    s_ghoTokenPool.setRateLimitAdmin(STRANGER);
  }
}

contract GhoTokenPoolEthereum_setBridgeLimit is GhoTokenPoolEthereumSetup {
  event BridgeLimitUpdated(uint256 oldBridgeLimit, uint256 newBridgeLimit);
  event BridgeLimitAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

  function testSetBridgeLimitAdminSuccess() public {
    assertEq(INITIAL_BRIDGE_LIMIT, s_ghoTokenPool.getBridgeLimit());

    uint256 newBridgeLimit = INITIAL_BRIDGE_LIMIT * 2;

    vm.expectEmit();
    emit BridgeLimitUpdated(INITIAL_BRIDGE_LIMIT, newBridgeLimit);

    vm.startPrank(AAVE_DAO);
    s_ghoTokenPool.setBridgeLimit(newBridgeLimit);

    assertEq(newBridgeLimit, s_ghoTokenPool.getBridgeLimit());

    // Bridge Limit Admin
    address bridgeLimitAdmin = address(28973509103597907);

    vm.expectEmit();
    emit BridgeLimitAdminUpdated(address(0), bridgeLimitAdmin);

    s_ghoTokenPool.setBridgeLimitAdmin(bridgeLimitAdmin);

    vm.startPrank(bridgeLimitAdmin);
    newBridgeLimit += 1;

    s_ghoTokenPool.setBridgeLimit(newBridgeLimit);

    assertEq(newBridgeLimit, s_ghoTokenPool.getBridgeLimit());
  }

  function testZeroBridgeLimitReverts() public {
    vm.stopPrank();
    vm.startPrank(AAVE_DAO);
    s_ghoTokenPool.setBridgeLimit(0);

    uint256 amount = 1;

    vm.expectRevert(abi.encodeWithSelector(UpgradeableLockReleaseTokenPool.BridgeLimitExceeded.selector, 0));
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: amount,
        localToken: address(s_token)
      })
    );
  }

  function testBridgeLimitBelowCurrent() public {
    // Increase current bridged amount to 10
    uint256 amount = 10e18;
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: amount,
        localToken: address(s_token)
      })
    );

    // Reduce bridge limit below current bridged amount
    vm.startPrank(AAVE_DAO);
    uint256 newBridgeLimit = amount - 1;
    s_ghoTokenPool.setBridgeLimit(newBridgeLimit);
    assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), amount);
    assertEq(s_ghoTokenPool.getBridgeLimit(), newBridgeLimit);
    assertGt(s_ghoTokenPool.getCurrentBridgedAmount(), s_ghoTokenPool.getBridgeLimit());

    // Lock reverts due to maxed out bridge limit
    vm.expectRevert(
      abi.encodeWithSelector(UpgradeableLockReleaseTokenPool.BridgeLimitExceeded.selector, newBridgeLimit)
    );
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: 1,
        localToken: address(s_token)
      })
    );

    // Increase bridge limit by 1
    vm.startPrank(AAVE_DAO);
    newBridgeLimit = amount + 1;
    s_ghoTokenPool.setBridgeLimit(newBridgeLimit);
    assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), amount);
    assertEq(s_ghoTokenPool.getBridgeLimit(), newBridgeLimit);
    assertGt(s_ghoTokenPool.getBridgeLimit(), s_ghoTokenPool.getCurrentBridgedAmount());

    // Bridge limit maxed out again
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: 1,
        localToken: address(s_token)
      })
    );
    assertEq(s_ghoTokenPool.getBridgeLimit(), s_ghoTokenPool.getCurrentBridgedAmount());
  }

  function testCurrentBridgedAmountRecover() public {
    // Reach maximum
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: INITIAL_BRIDGE_LIMIT,
        localToken: address(s_token)
      })
    );
    assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), INITIAL_BRIDGE_LIMIT);
    assertEq(s_ghoTokenPool.getBridgeLimit(), s_ghoTokenPool.getCurrentBridgedAmount());

    // Lock reverts due to maxed out bridge limit
    vm.expectRevert(
      abi.encodeWithSelector(UpgradeableLockReleaseTokenPool.BridgeLimitExceeded.selector, INITIAL_BRIDGE_LIMIT)
    );
    s_ghoTokenPool.lockOrBurn(
      Pool.LockOrBurnInV1({
        receiver: bytes(""),
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        originalSender: STRANGER,
        amount: 1,
        localToken: address(s_token)
      })
    );

    // Amount available to bridge recovers thanks to liquidity coming back
    UpgradeableTokenPool.ChainUpdate[] memory chainUpdate = new UpgradeableTokenPool.ChainUpdate[](1);
    bytes[] memory remotePoolAddresses = new bytes[](1);
    remotePoolAddresses[0] = abi.encode(s_sourcePool);
    chainUpdate[0] = UpgradeableTokenPool.ChainUpdate({
      remoteChainSelector: SOURCE_CHAIN_SELECTOR,
      remotePoolAddresses: remotePoolAddresses,
      remoteTokenAddress: abi.encode(s_sourceToken),
      outboundRateLimiterConfig: _getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: _getInboundRateLimiterConfig()
    });

    changePrank(AAVE_DAO);
    s_ghoTokenPool.applyChainUpdates(new uint64[](0), chainUpdate);

    uint256 amount = 10;
    deal(address(s_token), address(s_ghoTokenPool), amount);
    vm.startPrank(s_allowedOffRamp);
    s_ghoTokenPool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        amount: amount,
        remoteChainSelector: SOURCE_CHAIN_SELECTOR,
        receiver: OWNER,
        localToken: address(s_token),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
    assertEq(s_ghoTokenPool.getCurrentBridgedAmount(), INITIAL_BRIDGE_LIMIT - amount);
  }

  // Reverts

  function testSetBridgeLimitAdminReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, STRANGER));
    s_ghoTokenPool.setBridgeLimit(0);
  }
}

contract GhoTokenPoolEthereum_setBridgeLimitAdmin is GhoTokenPoolEthereumSetup {
  event BridgeLimitAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

  function testSetBridgeLimitAdminSuccess() public {
    assertEq(address(0), s_ghoTokenPool.getBridgeLimitAdmin());

    address bridgeLimitAdmin = address(28973509103597907);
    changePrank(AAVE_DAO);

    vm.expectEmit();
    emit BridgeLimitAdminUpdated(address(0), bridgeLimitAdmin);

    s_ghoTokenPool.setBridgeLimitAdmin(bridgeLimitAdmin);

    assertEq(bridgeLimitAdmin, s_ghoTokenPool.getBridgeLimitAdmin());
  }

  // Reverts

  function testSetBridgeLimitAdminReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert(OnlyCallableByOwner.selector);
    s_ghoTokenPool.setBridgeLimitAdmin(STRANGER);
  }
}

contract GhoTokenPoolEthereum_upgradeability is GhoTokenPoolEthereumSetup {
  function testInitialization() public {
    // Upgradeability
    assertEq(_getUpgradeableVersion(address(s_ghoTokenPool)), 1);
    vm.startPrank(PROXY_ADMIN);
    (bool ok, bytes memory result) = address(s_ghoTokenPool).staticcall(
      abi.encodeWithSelector(TransparentUpgradeableProxy.admin.selector)
    );
    assertTrue(ok, "proxy admin fetch failed");
    address decodedProxyAdmin = abi.decode(result, (address));
    assertEq(decodedProxyAdmin, PROXY_ADMIN, "proxy admin is wrong");
    assertEq(decodedProxyAdmin, _getProxyAdminAddress(address(s_ghoTokenPool)), "proxy admin is wrong");

    // TokenPool
    vm.startPrank(OWNER);
    assertEq(s_ghoTokenPool.getAllowList().length, 0);
    assertEq(s_ghoTokenPool.getAllowListEnabled(), false);
    assertEq(s_ghoTokenPool.getRmnProxy(), address(s_mockRMN));
    assertEq(s_ghoTokenPool.getRouter(), address(s_sourceRouter));
    assertEq(address(s_ghoTokenPool.getToken()), address(s_token));
    assertEq(s_ghoTokenPool.owner(), AAVE_DAO, "owner is wrong");
  }

  function testUpgrade() public {
    MockUpgradeable newImpl = new MockUpgradeable();
    bytes memory mockImpleParams = abi.encodeWithSignature("initialize()");
    vm.startPrank(PROXY_ADMIN);
    TransparentUpgradeableProxy(payable(address(s_ghoTokenPool))).upgradeToAndCall(address(newImpl), mockImpleParams);

    vm.startPrank(OWNER);
    assertEq(_getUpgradeableVersion(address(s_ghoTokenPool)), 2);
  }

  function testUpgradeAdminReverts() public {
    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_ghoTokenPool))).upgradeToAndCall(address(0), bytes(""));
    assertEq(_getUpgradeableVersion(address(s_ghoTokenPool)), 1);

    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_ghoTokenPool))).upgradeTo(address(0));
    assertEq(_getUpgradeableVersion(address(s_ghoTokenPool)), 1);
  }

  function testChangeAdmin() public {
    assertEq(_getProxyAdminAddress(address(s_ghoTokenPool)), PROXY_ADMIN);

    address newAdmin = makeAddr("newAdmin");
    vm.startPrank(PROXY_ADMIN);
    TransparentUpgradeableProxy(payable(address(s_ghoTokenPool))).changeAdmin(newAdmin);

    assertEq(_getProxyAdminAddress(address(s_ghoTokenPool)), newAdmin, "Admin change failed");
  }

  function testChangeAdminAdminReverts() public {
    assertEq(_getProxyAdminAddress(address(s_ghoTokenPool)), PROXY_ADMIN);

    address newAdmin = makeAddr("newAdmin");
    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_ghoTokenPool))).changeAdmin(newAdmin);

    assertEq(_getProxyAdminAddress(address(s_ghoTokenPool)), PROXY_ADMIN, "Unauthorized admin change");
  }
}
