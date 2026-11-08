// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {GhoToken} from "@aave-gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {stdError} from "forge-std/Test.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {EVM2EVMOnRamp} from "../../../onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOffRamp} from "../../../offRamp/EVM2EVMOffRamp.sol";
import {UpgradeableBurnMintTokenPool} from "../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";
import {Pool} from "../../../libraries/Pool.sol";
import {MockUpgradeable} from "../../mocks/MockUpgradeable.sol";

import {GhoTokenPoolRemoteSetup} from "./GhoTokenPoolRemoteSetup.t.sol";

contract GhoTokenPoolRemote_lockOrBurn is GhoTokenPoolRemoteSetup {
  function testSetupSuccess() public view {
    assertEq(address(s_burnMintERC677), address(s_pool.getToken()));
    assertEq(address(s_mockRMN), s_pool.getRmnProxy());
    assertEq(false, s_pool.getAllowListEnabled());
    assertEq("BurnMintTokenPool 1.5.1", s_pool.typeAndVersion());
  }

  function testPoolBurnSuccess() public {
    uint256 burnAmount = 20_000e18;
    // inflate facilitator level
    _inflateFacilitatorLevel(address(s_pool), address(s_burnMintERC677), burnAmount);

    deal(address(s_burnMintERC677), address(s_pool), burnAmount);
    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), burnAmount);

    vm.startPrank(s_burnMintOnRamp);

    vm.expectEmit();
    emit TokensConsumed(burnAmount);

    vm.expectEmit();
    emit Transfer(address(s_pool), address(0), burnAmount);

    vm.expectEmit();
    emit Burned(address(s_burnMintOnRamp), burnAmount);

    bytes4 expectedSignature = bytes4(keccak256("burn(uint256)"));
    vm.expectCall(address(s_burnMintERC677), abi.encodeWithSelector(expectedSignature, burnAmount));

    (uint256 preCapacity, uint256 preLevel) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(address(s_pool));

    s_pool.lockOrBurn(
      Pool.LockOrBurnInV1({
        originalSender: OWNER,
        receiver: bytes(""),
        amount: burnAmount,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677)
      })
    );

    // Facilitator checks
    (uint256 postCapacity, uint256 postLevel) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(
      address(s_pool)
    );
    assertEq(postCapacity, preCapacity);
    assertEq(preLevel - burnAmount, postLevel, "wrong facilitator bucket level");

    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), 0);
  }

  // Should not burn tokens if cursed.
  function testPoolBurnRevertNotHealthyReverts() public {
    s_mockRMN.setGlobalCursed(true);
    uint256 before = s_burnMintERC677.balanceOf(address(s_pool));
    vm.startPrank(s_burnMintOnRamp);

    vm.expectRevert(EVM2EVMOnRamp.CursedByRMN.selector);
    s_pool.lockOrBurn(
      Pool.LockOrBurnInV1({
        originalSender: OWNER,
        receiver: bytes(""),
        amount: 1e5,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677)
      })
    );

    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), before);
  }

  function testChainNotAllowedReverts() public {
    uint64 wrongChainSelector = 8838833;
    vm.expectRevert(abi.encodeWithSelector(UpgradeableTokenPool.ChainNotAllowed.selector, wrongChainSelector));
    s_pool.lockOrBurn(
      Pool.LockOrBurnInV1({
        originalSender: OWNER,
        receiver: bytes(""),
        amount: 1,
        remoteChainSelector: wrongChainSelector,
        localToken: address(s_burnMintERC677)
      })
    );
  }

  function testPoolBurnNoPrivilegesReverts() public {
    // Remove privileges
    vm.startPrank(AAVE_DAO);
    GhoToken(address(s_burnMintERC677)).removeFacilitator(address(s_pool));
    vm.stopPrank();

    uint256 amount = 1;
    vm.startPrank(s_burnMintOnRamp);
    vm.expectRevert(stdError.arithmeticError);
    s_pool.lockOrBurn(
      Pool.LockOrBurnInV1({
        originalSender: STRANGER,
        receiver: bytes(""),
        amount: amount,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677)
      })
    );
  }

  function testBucketLevelNotEnoughReverts() public {
    (, uint256 bucketLevel) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(address(s_pool));
    assertEq(bucketLevel, 0);

    uint256 amount = 1;
    vm.expectCall(address(s_burnMintERC677), abi.encodeWithSelector(GhoToken.burn.selector, amount));
    vm.expectRevert(stdError.arithmeticError);
    vm.startPrank(s_burnMintOnRamp);
    s_pool.lockOrBurn(
      Pool.LockOrBurnInV1({
        originalSender: STRANGER,
        receiver: bytes(""),
        amount: amount,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677)
      })
    );
  }

  function testTokenMaxCapacityExceededReverts() public {
    RateLimiter.Config memory rateLimiterConfig = _getOutboundRateLimiterConfig();
    uint256 capacity = rateLimiterConfig.capacity;
    uint256 amount = 10 * capacity;

    vm.expectRevert(
      abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_burnMintERC677))
    );
    vm.startPrank(s_burnMintOnRamp);
    s_pool.lockOrBurn(
      Pool.LockOrBurnInV1({
        originalSender: STRANGER,
        receiver: bytes(""),
        amount: amount,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677)
      })
    );
  }
}

contract GhoTokenPoolRemote_releaseOrMint is GhoTokenPoolRemoteSetup {
  function testPoolMintSuccess() public {
    uint256 amount = 1e19;
    vm.startPrank(s_burnMintOffRamp);
    vm.expectEmit();
    emit Transfer(address(0), OWNER, amount);
    s_pool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        receiver: OWNER,
        amount: amount,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
    assertEq(s_burnMintERC677.balanceOf(OWNER), amount);
  }

  function testPoolMintNotHealthyReverts() public {
    // Should not mint tokens if cursed.
    s_mockRMN.setGlobalCursed(true);
    uint256 before = s_burnMintERC677.balanceOf(OWNER);
    vm.startPrank(s_burnMintOffRamp);
    vm.expectRevert(EVM2EVMOffRamp.CursedByRMN.selector);
    s_pool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        receiver: OWNER,
        amount: 1e5,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
    assertEq(s_burnMintERC677.balanceOf(OWNER), before);
  }

  function testChainNotAllowedReverts() public {
    uint64 wrongChainSelector = 8838833;
    vm.expectRevert(abi.encodeWithSelector(UpgradeableTokenPool.ChainNotAllowed.selector, wrongChainSelector));
    s_pool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        receiver: STRANGER,
        amount: 1,
        remoteChainSelector: wrongChainSelector,
        localToken: address(s_burnMintERC677),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
  }

  function testPoolMintNoPrivilegesReverts() public {
    // Remove privileges
    vm.startPrank(AAVE_DAO);
    GhoToken(address(s_burnMintERC677)).removeFacilitator(address(s_pool));
    vm.stopPrank();

    uint256 amount = 1;
    vm.startPrank(s_burnMintOffRamp);
    vm.expectRevert("FACILITATOR_BUCKET_CAPACITY_EXCEEDED");
    s_pool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        receiver: STRANGER,
        amount: amount,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
  }

  function testBucketCapacityExceededReverts() public {
    // Mint all the bucket capacity
    (uint256 bucketCapacity, ) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(address(s_pool));
    _inflateFacilitatorLevel(address(s_pool), address(s_burnMintERC677), bucketCapacity);
    (uint256 currCapacity, uint256 currLevel) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(
      address(s_pool)
    );
    assertEq(currCapacity, currLevel);

    uint256 amount = 1;
    vm.expectCall(address(s_burnMintERC677), abi.encodeWithSelector(GhoToken.mint.selector, STRANGER, amount));
    vm.expectRevert("FACILITATOR_BUCKET_CAPACITY_EXCEEDED");
    vm.startPrank(s_burnMintOffRamp);
    s_pool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        receiver: STRANGER,
        amount: amount,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677),
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

    vm.expectRevert(
      abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_burnMintERC677))
    );
    vm.startPrank(s_burnMintOffRamp);
    s_pool.releaseOrMint(
      Pool.ReleaseOrMintInV1({
        originalSender: bytes(""),
        receiver: STRANGER,
        amount: amount,
        remoteChainSelector: DEST_CHAIN_SELECTOR,
        localToken: address(s_burnMintERC677),
        sourcePoolAddress: abi.encode(s_sourcePool),
        sourcePoolData: bytes(""),
        offchainTokenData: bytes("")
      })
    );
  }
}

contract GhoTokenPoolEthereum_upgradeability is GhoTokenPoolRemoteSetup {
  function testInitialization() public {
    // Upgradeability
    assertEq(_getUpgradeableVersion(address(s_pool)), 1);
    vm.startPrank(PROXY_ADMIN);
    (bool ok, bytes memory result) = address(s_pool).staticcall(
      abi.encodeWithSelector(TransparentUpgradeableProxy.admin.selector)
    );
    assertTrue(ok, "proxy admin fetch failed");
    address decodedProxyAdmin = abi.decode(result, (address));
    assertEq(decodedProxyAdmin, PROXY_ADMIN, "proxy admin is wrong");
    assertEq(decodedProxyAdmin, _getProxyAdminAddress(address(s_pool)), "proxy admin is wrong");

    // TokenPool
    vm.startPrank(OWNER);
    assertEq(s_pool.getAllowList().length, 0);
    assertEq(s_pool.getAllowListEnabled(), false);
    assertEq(s_pool.getRmnProxy(), address(s_mockRMN));
    assertEq(s_pool.getRouter(), address(s_sourceRouter));
    assertEq(address(s_pool.getToken()), address(s_burnMintERC677));
    assertEq(s_pool.owner(), AAVE_DAO, "owner is wrong");
  }

  function testUpgrade() public {
    MockUpgradeable newImpl = new MockUpgradeable();
    bytes memory mockImpleParams = abi.encodeWithSignature("initialize()");
    vm.startPrank(PROXY_ADMIN);
    TransparentUpgradeableProxy(payable(address(s_pool))).upgradeToAndCall(address(newImpl), mockImpleParams);

    vm.startPrank(OWNER);
    assertEq(_getUpgradeableVersion(address(s_pool)), 2);
  }

  function testUpgradeAdminReverts() public {
    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_pool))).upgradeToAndCall(address(0), bytes(""));
    assertEq(_getUpgradeableVersion(address(s_pool)), 1);

    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_pool))).upgradeTo(address(0));
    assertEq(_getUpgradeableVersion(address(s_pool)), 1);
  }

  function testChangeAdmin() public {
    assertEq(_getProxyAdminAddress(address(s_pool)), PROXY_ADMIN);

    address newAdmin = makeAddr("newAdmin");
    vm.startPrank(PROXY_ADMIN);
    TransparentUpgradeableProxy(payable(address(s_pool))).changeAdmin(newAdmin);

    assertEq(_getProxyAdminAddress(address(s_pool)), newAdmin, "Admin change failed");
  }

  function testChangeAdminAdminReverts() public {
    assertEq(_getProxyAdminAddress(address(s_pool)), PROXY_ADMIN);

    address newAdmin = makeAddr("newAdmin");
    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_pool))).changeAdmin(newAdmin);

    assertEq(_getProxyAdminAddress(address(s_pool)), PROXY_ADMIN, "Unauthorized admin change");
  }
}

contract GhoTokenPoolRemote_setChainRateLimiterConfig is GhoTokenPoolRemoteSetup {
  event ConfigChanged(RateLimiter.Config);
  event ChainConfigured(
    uint64 chainSelector,
    RateLimiter.Config outboundRateLimiterConfig,
    RateLimiter.Config inboundRateLimiterConfig
  );

  uint64 internal s_remoteChainSelector;

  function setUp() public virtual override {
    GhoTokenPoolRemoteSetup.setUp();
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
    s_pool.applyChainUpdates(new uint64[](0), chainUpdates);
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

    uint256 oldOutboundTokens = s_pool.getCurrentOutboundRateLimiterState(s_remoteChainSelector).tokens;
    uint256 oldInboundTokens = s_pool.getCurrentInboundRateLimiterState(s_remoteChainSelector).tokens;

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
    s_pool.setChainRateLimiterConfig(s_remoteChainSelector, newOutboundConfig, newInboundConfig);

    uint256 expectedTokens = RateLimiter._min(newOutboundConfig.capacity, oldOutboundTokens);

    RateLimiter.TokenBucket memory bucket = s_pool.getCurrentOutboundRateLimiterState(s_remoteChainSelector);
    assertEq(bucket.capacity, newOutboundConfig.capacity);
    assertEq(bucket.rate, newOutboundConfig.rate);
    assertEq(bucket.tokens, expectedTokens);
    assertEq(bucket.lastUpdated, newTime);

    expectedTokens = RateLimiter._min(newInboundConfig.capacity, oldInboundTokens);

    bucket = s_pool.getCurrentInboundRateLimiterState(s_remoteChainSelector);
    assertEq(bucket.capacity, newInboundConfig.capacity);
    assertEq(bucket.rate, newInboundConfig.rate);
    assertEq(bucket.tokens, expectedTokens);
    assertEq(bucket.lastUpdated, newTime);
  }

  function testOnlyOwnerOrRateLimitAdminSuccess() public {
    address rateLimiterAdmin = address(28973509103597907);

    changePrank(AAVE_DAO);
    s_pool.setRateLimitAdmin(rateLimiterAdmin);

    changePrank(rateLimiterAdmin);

    s_pool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      _getOutboundRateLimiterConfig(),
      _getInboundRateLimiterConfig()
    );

    changePrank(AAVE_DAO);

    s_pool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      _getOutboundRateLimiterConfig(),
      _getInboundRateLimiterConfig()
    );
  }

  // Reverts

  function testOnlyOwnerReverts() public {
    changePrank(STRANGER);

    vm.expectRevert(abi.encodeWithSelector(UpgradeableTokenPool.Unauthorized.selector, STRANGER));
    s_pool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      _getOutboundRateLimiterConfig(),
      _getInboundRateLimiterConfig()
    );
  }

  function testNonExistentChainReverts() public {
    uint64 wrongChainSelector = 9084102894;

    vm.expectRevert(abi.encodeWithSelector(UpgradeableTokenPool.NonExistentChain.selector, wrongChainSelector));
    changePrank(AAVE_DAO);
    s_pool.setChainRateLimiterConfig(
      wrongChainSelector,
      _getOutboundRateLimiterConfig(),
      _getInboundRateLimiterConfig()
    );
  }
}

contract GhoTokenPoolRemote_setRateLimitAdmin is GhoTokenPoolRemoteSetup {
  function testSetRateLimitAdminSuccess() public {
    assertEq(address(0), s_pool.getRateLimitAdmin());
    changePrank(AAVE_DAO);
    s_pool.setRateLimitAdmin(OWNER);
    assertEq(OWNER, s_pool.getRateLimitAdmin());
  }

  // Reverts

  function testSetRateLimitAdminReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert(OnlyCallableByOwner.selector);
    s_pool.setRateLimitAdmin(STRANGER);
  }
}

contract GhoTokenPoolRemote_directMint is GhoTokenPoolRemoteSetup {
  function testFuzzDirectMintSuccess(uint256 amount) public {
    amount = bound(amount, 1, type(uint128).max); // current pool capacity

    address oldTokePool = makeAddr("oldTokePool");

    changePrank(AAVE_DAO);
    vm.expectEmit(address(s_burnMintERC677));
    emit Transfer(address(0), oldTokePool, amount);
    s_pool.directMint(oldTokePool, amount);

    assertEq(s_burnMintERC677.balanceOf(oldTokePool), amount);
    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), 0);
    assertEq(GhoToken(address(s_burnMintERC677)).getFacilitator(address(s_pool)).bucketLevel, amount);
  }

  // Reverts

  function testDirectMintReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert(OnlyCallableByOwner.selector);
    s_pool.directMint(makeAddr("oldFacilitator"), 13e7);
  }
}

contract GhoTokenPoolRemote_directBurn is GhoTokenPoolRemoteSetup {
  function testFuzzDirectBurnSuccess(uint256 amount) public {
    amount = bound(amount, 1, type(uint128).max); // bound to bucket capacity
    // prank previously bridged supply
    vm.startPrank(address(s_pool));
    s_burnMintERC677.mint(address(s_pool), amount);

    vm.startPrank(AAVE_DAO);
    s_pool.directBurn(amount);

    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), 0);
    assertEq(GhoToken(address(s_burnMintERC677)).getFacilitator(address(s_pool)).bucketLevel, 0);
  }

  function testDirectBurnReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert(OnlyCallableByOwner.selector);
    s_pool.directBurn(13e7);
  }
}

contract GhoTokenPoolRemote_migrateLiquidity is GhoTokenPoolRemoteSetup {
  UpgradeableBurnMintTokenPool internal s_oldBurnMintTokenPool;

  function setUp() public override {
    super.setUp();

    s_oldBurnMintTokenPool = UpgradeableBurnMintTokenPool(
      _deployUpgradeableBurnMintTokenPool(
        address(s_burnMintERC677),
        address(s_mockRMN),
        address(s_sourceRouter),
        AAVE_DAO,
        PROXY_ADMIN
      )
    );

    changePrank(AAVE_DAO);
    GhoToken(address(s_burnMintERC677)).addFacilitator(
      address(s_oldBurnMintTokenPool),
      "OldTokenPool",
      uint128(INITIAL_BRIDGE_LIMIT)
    );

    // mock existing supply offRamped by old token pool (not using `directMint` for clarity)
    // which is circulating on remote chain
    changePrank(address(s_oldBurnMintTokenPool));
    s_burnMintERC677.mint(makeAddr("users"), INITIAL_BRIDGE_LIMIT);
  }

  function testFuzzMigrateFacilitator(uint256 amount) public {
    amount = bound(amount, 1, INITIAL_BRIDGE_LIMIT); // old pool bucket level
    changePrank(AAVE_DAO);

    assertEq(
      GhoToken(address(s_burnMintERC677)).getFacilitator(address(s_oldBurnMintTokenPool)).bucketLevel,
      INITIAL_BRIDGE_LIMIT
    );
    assertEq(GhoToken(address(s_burnMintERC677)).getFacilitator(address(s_pool)).bucketLevel, 0);

    // note: these two operations should be done atomically such that there no unbacked tokens
    // in circulation at any point
    // 1. mint tokens to old pool
    vm.expectEmit(address(s_burnMintERC677));
    emit Transfer(address(0), address(s_oldBurnMintTokenPool), amount);
    s_pool.directMint(address(s_oldBurnMintTokenPool), amount);

    // 2. burn tokens from old pool
    vm.expectEmit(address(s_burnMintERC677));
    emit Transfer(address(s_oldBurnMintTokenPool), address(0), amount);
    s_oldBurnMintTokenPool.directBurn(amount);

    assertEq(s_burnMintERC677.balanceOf(address(s_oldBurnMintTokenPool)), 0);
    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), 0);

    assertEq(
      GhoToken(address(s_burnMintERC677)).getFacilitator(address(s_oldBurnMintTokenPool)).bucketLevel,
      INITIAL_BRIDGE_LIMIT - amount
    );
    assertEq(GhoToken(address(s_burnMintERC677)).getFacilitator(address(s_pool)).bucketLevel, amount);
  }
}
