// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {ProxyHelpers} from 'aave-helpers/ProxyHelpers.sol';
import {TestWithExecutor} from 'aave-helpers/GovHelpers.sol';
import {ICollector} from '../src/interfaces/ICollector.sol';
import {IInitializableAdminUpgradeabilityProxy} from '../src/interfaces/IInitializableAdminUpgradeabilityProxy.sol';
import {UpgradeAaveCollectorPayload} from '../src/contracts/payloads/UpgradeAaveCollectorPayload.sol';
import {Collector} from '../src/contracts/Collector.sol';

abstract contract BaseTest is TestWithExecutor {
  UpgradeAaveCollectorPayload public payload;
  address internal _collectorProxy;
  address internal _collectorImpl;
  address internal _proxyAdmin;
  address internal _newFundsAdmin;
  uint256 internal _streamId;
  IERC20 internal _token;

  function _setUp(
    address collectorProxy,
    address proxyAdmin,
    address newFundsAdmin,
    uint256 streamId,
    address executor,
    IERC20 token
  ) public {
    _collectorProxy = collectorProxy;
    _proxyAdmin = proxyAdmin;
    _newFundsAdmin = newFundsAdmin;
    _streamId = streamId;
    _token = token;

    _collectorImpl = address(new Collector());

    payload = new UpgradeAaveCollectorPayload(
      _collectorProxy,
      _collectorImpl,
      _proxyAdmin,
      _newFundsAdmin,
      _streamId
    );
    _selectPayloadExecutor(executor);
  }

  function testExecuteProxyAdminAndFundsAdminChanged() public {
    ICollector collector = ICollector(_collectorProxy);
    address implBefore = ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(
      vm,
      _collectorProxy
    );

    uint256 currentStreamId;
    if (_streamId == 0) {
      currentStreamId = collector.getNextStreamId();
    }

    // Act
    _executePayload(address(payload));

    // Assert
    address implAfter = ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(
      vm,
      _collectorProxy
    );

    // implementation should change
    assertTrue(implBefore != implAfter);
    assertTrue(implAfter == _collectorImpl);

    // check fundsAdmin = short executor/guardian
    assertEq(collector.getFundsAdmin(), _newFundsAdmin);

    // check that funds admin is not the proxy admin
    vm.startPrank(_proxyAdmin);

    IInitializableAdminUpgradeabilityProxy proxy = IInitializableAdminUpgradeabilityProxy(
      _collectorProxy
    );

    address newAdmin = proxy.admin();
    assertEq(newAdmin, _proxyAdmin);

    // change admin to someone else
    address anotherAdmin = vm.addr(0xA11BBB);
    proxy.changeAdmin(anotherAdmin);

    vm.stopPrank();

    // check that new proxy admin is in charge
    vm.startPrank(anotherAdmin);
    assertEq(proxy.admin(), anotherAdmin);

    vm.stopPrank();

    // check that stream id is set or not modified
    uint256 newStreamId = collector.getNextStreamId();
    if (_streamId > 0) {
      assertEq(newStreamId, _streamId);
    } else {
      assertEq(newStreamId, currentStreamId);
    }

    address recipient = vm.addr(0xA11CEB);
    address anotherFundsAdmin = vm.addr(0xA11CCC);

    // act as funds admin
    vm.startPrank(_newFundsAdmin);

    // should transfer
    collector.transfer(_token, recipient, 1000);

    // should approve
    collector.approve(_token, recipient, 1000);

    // change funds admin to someone else
    collector.setFundsAdmin(anotherFundsAdmin);

    vm.stopPrank();

    // act as new funds admin
    vm.startPrank(anotherFundsAdmin);

    // should transfer
    collector.transfer(_token, recipient, 1000);
  }
}
