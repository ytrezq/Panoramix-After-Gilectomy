// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import 'forge-std/Vm.sol';
import 'forge-std/StdJson.sol';
import {AaveSafetyModule} from 'aave-address-book/AaveSafetyModule.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {AaveMisc} from 'aave-address-book/AaveMisc.sol';
import {StakedAaveV3} from '../src/contracts/StakedAaveV3.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ProxyAdmin} from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';

contract StkAaveBalancesTest is Test {
  using stdJson for string;

  StakedAaveV3 stkAave = StakedAaveV3(AaveSafetyModule.STK_AAVE);

  address[] users;
  mapping(address => uint256) balancesBefore;
  mapping(address => uint256) balancesAfter;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 18841250);

    _getUsers();
  }

  function testBalances() public {
    StakedAaveV3 stkAaveImpl = new StakedAaveV3(
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING),
      IERC20(AaveV3EthereumAssets.AAVE_UNDERLYING),
      172800,
      AaveMisc.ECOSYSTEM_RESERVE,
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      3155692600
    );

    _getBalances(true);

    hoax(AaveGovernanceV2.LONG_EXECUTOR);
    ProxyAdmin(AaveMisc.PROXY_ADMIN_ETHEREUM_LONG).upgradeAndCall(
      TransparentUpgradeableProxy(payable(address(stkAave))),
      address(stkAaveImpl),
      abi.encodeWithSignature('initialize()')
    );

    _getBalances(false);

    //    _validateBalances();
  }

  function _validateBalances() internal {
    for (uint256 i; i < users.length; i++) {
      address user = users[i];
      assertEq(balancesBefore[user], balancesAfter[user]);
    }
  }

  function _getBalances(bool before) internal {
    for (uint256 i; i < users.length; i++) {
      address user = users[i];
      if (before) {
        balancesBefore[user] = IERC20(address(stkAave)).balanceOf(user);
      } else {
        balancesAfter[user] = IERC20(address(stkAave)).balanceOf(user);
      }
    }
  }

  function _getUsers() internal {
    string memory path = './tests/utils/stkHolders.json';

    string memory json = vm.readFile(string(abi.encodePacked(path)));
    users = abi.decode(json.parseRaw('.holders'), (address[]));
  }
}
