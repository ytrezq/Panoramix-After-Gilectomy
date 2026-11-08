// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { stdError } from "@forge-std/Test.sol";

import { MockSwapRouter } from "tests/mock/MockSwapRouter.sol";
import { MockTokenPermit } from "tests/mock/MockTokenPermit.sol";

import "contracts/parallelizer/Storage.sol";
import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";

contract RewardHandlerTest is Fixture {
  event RewardsSoldFor(address indexed tokenObtained, uint256 balanceUpdate);

  MockSwapRouter router;
  IERC20 tokenA;
  IERC20 tokenB;

  function setUp() public override {
    super.setUp();
    tokenA = IERC20(address(new MockTokenPermit("tokenA", "tokenA", 18)));
    tokenB = IERC20(address(new MockTokenPermit("tokenA", "tokenA", 9)));

    router = new MockSwapRouter();
    hoax(governor);
    parallelizer.setSwapRouter(address(router));
  }

  function test_RevertWhen_SellRewards_NotTrusted() public {
    startHoax(alice);
    vm.expectRevert(Errors.NotTrusted.selector);
    bytes memory data;
    parallelizer.sellRewards(0, data);
  }

  function test_RevertWhen_SellRewards_NoApproval() public {
    vm.startPrank(guardian);
    bytes memory payload =
      abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(tokenA), address(tokenB));
    vm.expectRevert();
    parallelizer.sellRewards(0, payload);
    vm.stopPrank();
  }

  function test_RevertWhen_SellRewards_NoIncrease() public {
    bytes memory payload =
      abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(tokenA), address(tokenB));
    vm.startPrank(governor);

    deal(address(tokenA), address(parallelizer), 100);
    deal(address(tokenB), address(router), 100);
    parallelizer.changeAllowance(tokenA, address(router), 100);
    vm.expectRevert(Errors.InvalidSwap.selector);
    parallelizer.sellRewards(0, payload);
    vm.stopPrank();
  }

  function test_RevertWhen_SellRewards_TooSmallAmountOut() public {
    bytes memory payload =
      abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(tokenA), address(eurA));
    vm.startPrank(governor);

    deal(address(tokenA), address(parallelizer), 100);
    deal(address(eurA), address(router), 100);
    parallelizer.changeAllowance(tokenA, address(router), 100);
    vm.expectRevert(Errors.TooSmallAmountOut.selector);
    parallelizer.sellRewards(1000, payload);
    vm.stopPrank();
  }

  function test_RevertWhen_SellRewards_EmptyErrorMessage() public {
    bytes memory payload =
      abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(tokenA), address(tokenB));
    vm.startPrank(governor);

    deal(address(tokenA), address(parallelizer), 100);
    deal(address(tokenB), address(router), 100);
    parallelizer.changeAllowance(tokenA, address(router), 100);
    router.setRevertStatuses(true, false);
    vm.expectRevert(Errors.RewardSwapFailed.selector);
    parallelizer.sellRewards(0, payload);
    vm.stopPrank();
  }

  function test_RevertWhen_SellRewards_ErrorMessage() public {
    bytes memory payload =
      abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(tokenA), address(tokenB));
    vm.startPrank(governor);

    deal(address(tokenA), address(parallelizer), 100);
    deal(address(tokenB), address(router), 100);
    parallelizer.changeAllowance(tokenA, address(router), 100);
    router.setRevertStatuses(false, true);
    vm.expectRevert("wrong swap");
    parallelizer.sellRewards(0, payload);
    vm.stopPrank();
  }

  function test_RevertWhen_SellRewards_InvalidSwapBecauseTokenSold() public {
    bytes memory payload = abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(eurA), address(eurB));
    vm.startPrank(governor);

    deal(address(eurA), address(parallelizer), 100);
    deal(address(eurB), address(router), 100);
    parallelizer.changeAllowance(eurA, address(router), 100);
    vm.expectRevert(Errors.InvalidSwap.selector);
    parallelizer.sellRewards(0, payload);
    vm.stopPrank();
  }

  function test_SellRewards_WithOneTokenIncrease() public {
    bytes memory payload =
      abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(tokenA), address(eurA));
    vm.startPrank(governor);

    deal(address(tokenA), address(parallelizer), 100);
    deal(address(eurA), address(router), 100);
    parallelizer.changeAllowance(tokenA, address(router), 100);
    vm.expectEmit(address(parallelizer));
    emit RewardsSoldFor(address(eurA), 100);
    parallelizer.sellRewards(0, payload);
    vm.stopPrank();
  }

  function test_RevertWhen_SellRewards_TokenPSold() public {
    bytes memory payload =
      abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(tokenP), address(eurA));
    vm.startPrank(governor);

    deal(address(tokenP), address(parallelizer), 100);
    deal(address(eurA), address(router), 100);
    parallelizer.changeAllowance(IERC20(address(tokenP)), address(router), 100);
    vm.expectRevert(Errors.InvalidTokens.selector);
    parallelizer.sellRewards(0, payload);
    vm.stopPrank();
  }

  function test_SellRewards_WithOneTokenIncreaseAndTrusted() public {
    bytes memory payload =
      abi.encodeWithSelector(MockSwapRouter.swap.selector, 100, 100, address(tokenA), address(eurA));
    vm.startPrank(governor);
    parallelizer.toggleTrusted(alice, TrustedType.Seller);
    parallelizer.changeAllowance(tokenA, address(router), 100);
    vm.stopPrank();

    deal(address(tokenA), address(parallelizer), 100);
    deal(address(eurA), address(router), 100);

    vm.expectEmit(address(parallelizer));
    emit RewardsSoldFor(address(eurA), 100);
    vm.prank(alice);
    parallelizer.sellRewards(0, payload);
  }
}

contract Test_SwapRouter is Fixture {
  event SwapRouterUpdated(address indexed swapRouter);

  function test_SetSwapRouter_UpdatesTheLiveRouter() public {
    assertEq(parallelizer.getSwapRouter(), address(0), "no router before governance sets one");

    vm.expectEmit(address(parallelizer));
    emit SwapRouterUpdated(bob);
    hoax(governor);
    parallelizer.setSwapRouter(bob);

    assertEq(parallelizer.getSwapRouter(), bob);
  }

  function test_RevertWhen_SetSwapRouterIsZero() public {
    hoax(governor);
    vm.expectRevert(Errors.ZeroAddress.selector);
    parallelizer.setSwapRouter(address(0));
  }

  function test_RevertWhen_SetSwapRouterNotGovernor() public {
    hoax(guardian);
    vm.expectRevert(abi.encodeWithSelector(Errors.AccessManagedUnauthorized.selector, guardian));
    parallelizer.setSwapRouter(bob);
  }

  /// @dev A raw call to address zero would report success and leave the swap silently unperformed
  function test_RevertWhen_SellRewardsBeforeARouterIsSet() public {
    bytes memory payload;
    hoax(governor);
    vm.expectRevert(Errors.ZeroAddress.selector);
    parallelizer.sellRewards(0, payload);
  }
}
