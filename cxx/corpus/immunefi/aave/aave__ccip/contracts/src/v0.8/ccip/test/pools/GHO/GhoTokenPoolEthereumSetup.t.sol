// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {GhoToken} from "@aave-gho-core/gho/GhoToken.sol";

import {BaseTest} from "../../BaseTest.t.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {Router} from "../../../Router.sol";
import {IERC20} from "../../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RouterSetup} from "../../router/RouterSetup.t.sol";
import {BaseTest} from "../../BaseTest.t.sol";
import {GhoBaseTest} from "./GhoBaseTest.t.sol";

contract GhoTokenPoolEthereumSetup is RouterSetup, GhoBaseTest {
  IERC20 internal s_token;
  UpgradeableLockReleaseTokenPool internal s_ghoTokenPool;

  address internal s_allowedOnRamp = address(123);
  address internal s_allowedOffRamp = address(234);

  address internal s_sourcePool = makeAddr("source_pool");
  address internal s_sourceToken = makeAddr("source_token");

  function setUp() public virtual override(RouterSetup, BaseTest) {
    RouterSetup.setUp();

    // GHO deployment
    GhoToken ghoToken = new GhoToken(AAVE_DAO);
    s_token = IERC20(address(ghoToken));
    deal(address(s_token), OWNER, type(uint128).max);

    // Set up UpgradeableTokenPool with permission to mint/burn
    s_ghoTokenPool = UpgradeableLockReleaseTokenPool(
      _deployUpgradeableLockReleaseTokenPool(
        address(s_token),
        address(s_mockRMN),
        address(s_sourceRouter),
        AAVE_DAO,
        INITIAL_BRIDGE_LIMIT,
        PROXY_ADMIN
      )
    );

    UpgradeableTokenPool.ChainUpdate[] memory chainUpdate = new UpgradeableTokenPool.ChainUpdate[](1);
    bytes[] memory remotePoolAddresses = new bytes[](1);
    remotePoolAddresses[0] = abi.encode(s_sourcePool);

    chainUpdate[0] = UpgradeableTokenPool.ChainUpdate({
      remoteChainSelector: DEST_CHAIN_SELECTOR,
      remotePoolAddresses: remotePoolAddresses,
      remoteTokenAddress: abi.encode(s_sourceToken),
      outboundRateLimiterConfig: _getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: _getInboundRateLimiterConfig()
    });

    changePrank(AAVE_DAO);
    s_ghoTokenPool.applyChainUpdates(new uint64[](0), chainUpdate);
    s_ghoTokenPool.setRebalancer(OWNER);
    changePrank(OWNER);

    Router.OnRamp[] memory onRampUpdates = new Router.OnRamp[](1);
    Router.OffRamp[] memory offRampUpdates = new Router.OffRamp[](1);
    onRampUpdates[0] = Router.OnRamp({destChainSelector: DEST_CHAIN_SELECTOR, onRamp: s_allowedOnRamp});
    offRampUpdates[0] = Router.OffRamp({sourceChainSelector: SOURCE_CHAIN_SELECTOR, offRamp: s_allowedOffRamp});
    s_sourceRouter.applyRampUpdates(onRampUpdates, new Router.OffRamp[](0), offRampUpdates);
  }
}
