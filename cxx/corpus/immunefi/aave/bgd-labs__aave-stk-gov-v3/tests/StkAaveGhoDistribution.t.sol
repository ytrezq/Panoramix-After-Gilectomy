// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {GovHelpers} from 'aave-helpers/GovHelpers.sol';
import {StakedTokenV3} from '../src/contracts/StakedTokenV3.sol';
import {IInitializableAdminUpgradeabilityProxy} from '../src/interfaces/IInitializableAdminUpgradeabilityProxy.sol';
import {StakedAaveV3} from '../src/contracts/StakedAaveV3.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {AaveMisc} from 'aave-address-book/AaveMisc.sol';
import {AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {IGhoVariableDebtTokenTransferHook} from '../src/interfaces/IGhoVariableDebtTokenTransferHook.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract BaseTest is Test {
  constructor() {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 18636130);
  }
}

contract GhoDistributionGasTest is BaseTest, StakedAaveV3 {
  address ghoToken = 0x786dBff3f1292ae8F92ea68Cf93c30b34B1ed04B;

  event Mint(
    address indexed caller,
    address indexed onBehalfOf,
    uint256 value,
    uint256 balanceIncrease,
    uint256 index
  );

  function setUp() public {}

  constructor()
    BaseTest()
    StakedAaveV3(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING),
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING),
      172800,
      AaveMisc.ECOSYSTEM_RESERVE,
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      3155692600
    )
  {
    ghoDebtToken = IGhoVariableDebtTokenTransferHook(ghoToken);
  }

  function test_transferWithCorrectGasLimit() public {
    address from = 0xE831C8903de820137c13681E78A5780afDdf7697;
    address to = address(123415);
    uint256 fromBalance = 10 ether;
    uint256 toBalance = 0 ether;

    uint256 amount = 1 ether;
    // expect execution to complete
    vm.startPrank(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    vm.expectCallMinGas(
      ghoToken,
      0,
      220_000,
      abi.encodeWithSelector(
        IGhoVariableDebtTokenTransferHook.updateDiscountDistribution.selector,
        from,
        to,
        fromBalance,
        toBalance,
        amount
      )
    );
    vm.expectEmit(true, true, false, true);
    emit Transfer(address(0), from, 41185113828714);
    vm.expectEmit(true, true, false, true);
    emit Mint(
      address(0),
      from,
      41185113828714,
      41185113828714,
      1008020889040822120071191507
    );
    _updateDiscountDistribution(
      ghoToken,
      from,
      to,
      fromBalance,
      toBalance,
      amount
    );
    vm.stopPrank();
  }

  // test to make external call revert but due other reason different than out of gas
  function test_transferWithCorrectGasButErrorsOut() public {
    address from = 0xE831C8903de820137c13681E78A5780afDdf7697;
    address to = address(123415);
    uint256 fromBalance = 10 ether;
    uint256 toBalance = 0 ether;

    uint256 amount = 1 ether;

    // expect error but not revert
    this.updateDiscountDistribution(
      ghoToken,
      from,
      to,
      fromBalance,
      toBalance,
      amount
    );
  }

  // test to make external call revert due to not enough gas
  function test_transferWithIncorrectGas() public {
    uint256 insufficientGasLimit = 4_000;

    address from = 0xE831C8903de820137c13681E78A5780afDdf7697;
    address to = address(123415);
    uint256 fromBalance = 10 ether;
    uint256 toBalance = 0 ether;

    uint256 amount = 1 ether;

    // reverts because there is not enough gas
    vm.expectRevert();
    this.updateDiscountDistribution{gas: insufficientGasLimit}(
      ghoToken,
      from,
      to,
      fromBalance,
      toBalance,
      amount
    );
  }

  function updateDiscountDistribution(
    address cachedGhoDebtToken,
    address from,
    address to,
    uint256 fromBalanceBefore,
    uint256 toBalanceBefore,
    uint256 amount
  ) external {
    _updateDiscountDistribution(
      cachedGhoDebtToken,
      from,
      to,
      fromBalanceBefore,
      toBalanceBefore,
      amount
    );
  }
}
