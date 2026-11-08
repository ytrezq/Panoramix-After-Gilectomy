pragma solidity ^0.8.19;

import 'forge-std/console2.sol';
import 'forge-std/Vm.sol';

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Ownable} from "solidity-utils/contracts/oz-common/Ownable.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {IRescuable} from "solidity-utils/contracts/utils/interfaces/IRescuable.sol";

import {IBaseCrossChainController} from "../../../src/contracts/interfaces/IBaseCrossChainController.sol";
import {ICrossChainForwarder} from "../../../src/contracts/interfaces/ICrossChainForwarder.sol";
import {ICrossChainReceiver} from "../../../src/contracts/interfaces/ICrossChainReceiver.sol";
import {IBaseAdapter} from "../../../src/contracts/adapters/IBaseAdapter.sol";

import {BaseIntegrationTest} from "../BaseIntegrationTest.sol";

contract BaseStateTest is BaseIntegrationTest {

  struct AdapterLink {
    address localAdapter;
    address destinationAdapter;
  }

  struct AdaptersConfig {
    uint256 chainId;
    AdapterLink[] adapters;
  }

  struct TrustedRemotesConfig {
    uint256 chainId;
    address remoteCrossChainControllerAddress;
  }

  function _test_fork(
    uint256 _fork,
    string memory _forkName
  ) internal {
    uint256 fork = vm.activeFork();

    assertEq(fork, _fork, "Fork should be correct");

    console2.log("Active fork is %s", _forkName);
  }

  function _test_proxy_admin(
    address _proxyAdmin,
    address _cccAddress,
    address _cccImplAddress,
    address _daoAgent
  ) internal {
    address proxyAdminOwner = Ownable(_proxyAdmin).owner();

    console2.log("ProxyAdmin address: %s", _proxyAdmin);
    console2.log("ProxyAdmin owner: %s", proxyAdminOwner);

    ProxyAdmin proxyAdminContract = ProxyAdmin(_proxyAdmin);
    ITransparentUpgradeableProxy cccProxy = ITransparentUpgradeableProxy(_cccAddress);

    address proxyImp = proxyAdminContract.getProxyImplementation(cccProxy);
    address proxyAdminAddress = proxyAdminContract.getProxyAdmin(cccProxy);

    assertEq(proxyAdminOwner, _daoAgent, "ProxyAdmin owner should be DAO agent");
    console2.log("ProxyAdmin owner is DAO agent");

    assertEq(proxyAdminAddress, _proxyAdmin, "ProxyAdmin for CrossChainController should be ProxyAdmin");
    console2.log("CCC proxy admin address: %s", proxyAdminAddress);

    assertEq(proxyImp, _cccImplAddress, "CrossChainController implementation should be CrossChainControllerImpl");
    console2.log("CCC proxy implementation address: %s", proxyImp);
  }

  function _test_ccc_owners(
    address _cccAddress,
    address _daoAgent
  ) internal {
    address cccOwner = Ownable(_cccAddress).owner();
    address cccGuardian = OwnableWithGuardian(_cccAddress).guardian();
    address cccRescuer = IRescuable(_cccAddress).whoCanRescue();

    console2.log("CrossChainController address: %s", _cccAddress);
    console2.log("CrossChainController owner: %s", cccOwner);
    console2.log("CrossChainController guardian: %s", cccGuardian);
    console2.log("CrossChainController rescuer: %s", cccRescuer);

    assertEq(cccOwner, _daoAgent, "CrossChainController owner should be LIDO_DAO");
    console2.log("CrossChainController owner is DAO agent");

    assertEq(cccGuardian, ZERO_ADDRESS, "CrossChainController guardian should be ZERO");
    console2.log("CrossChainController guardian is ZERO");

    assertEq(cccRescuer, _daoAgent, "CrossChainController rescuer should be LIDO_DAO");
    console2.log("CrossChainController rescuer is DAO agent");
  }

  function _test_ccc_funds(
    address _cccAddress,
    uint256 _expectedBalance
  ) internal {
    console2.log("CrossChainController balance: %s", address(_cccAddress).balance);

    assertLe(address(_cccAddress).balance, _expectedBalance, "CrossChainController balance should be less than expected value");
    assertGt(address(_cccAddress).balance, _expectedBalance - 1e16, "CrossChainController balance should be greater than expected value minus 0.01 ETH");
    console2.log("CrossChainController balance is correct");
  }

  function _test_ccc_impl(
    address _cccImplAddress
  ) internal {
    address cccImplOwner = Ownable(_cccImplAddress).owner();
    address cccImplGuardian = OwnableWithGuardian(_cccImplAddress).guardian();
    address cccRescuer = IRescuable(_cccImplAddress).whoCanRescue();

    console2.log("CrossChainControllerImpl address: %s", _cccImplAddress);
    console2.log("CrossChainControllerImpl owner: %s", cccImplOwner);
    console2.log("CrossChainControllerImpl guardian: %s", cccImplGuardian);
    console2.log("CrossChainControllerImpl rescuer: %s", cccRescuer);

    assertEq(cccImplOwner, DEAD_ADDRESS, "CrossChainControllerImpl owner should be DEAD");
    console2.log("CrossChainControllerImpl owner is DEAD");

    assertEq(cccImplGuardian, ZERO_ADDRESS, "CrossChainControllerImpl guardian should be ZERO");
    console2.log("CrossChainControllerImpl guardian is ZERO");

    assertEq(cccRescuer, DEAD_ADDRESS, "CrossChainController rescuer should be DEAD");
    console2.log("CrossChainController rescuer is DEAD");
  }

  function _test_ccf_adapters(
    address _ccfAddress,
    AdaptersConfig[] memory _expectedAdapters
  ) internal {
    ICrossChainForwarder ccf = ICrossChainForwarder(_ccfAddress);

    for (uint256 i = 0; i < _expectedAdapters.length; i++) {
      uint256 chainId = _expectedAdapters[i].chainId;

      ICrossChainForwarder.ChainIdBridgeConfig[] memory bridgeAdapters = ccf.getForwarderBridgeAdaptersByChain(chainId);

      assertEq(bridgeAdapters.length, _expectedAdapters[i].adapters.length, "CrossChainForwarder bridge adapters count should match expected value");
      console2.log("CrossChainForwarder adapters: %s", bridgeAdapters.length);
      console2.log("CrossChainForwarder adapters count is correct for chainId: %s", chainId);

      for (uint256 j = 0; j < bridgeAdapters.length; j++) {
        ICrossChainForwarder.ChainIdBridgeConfig memory adapter = bridgeAdapters[j];

        assertEq(adapter.currentChainBridgeAdapter, _expectedAdapters[i].adapters[j].localAdapter, "localAdapter should match expected value");
        assertEq(adapter.destinationBridgeAdapter, _expectedAdapters[i].adapters[j].destinationAdapter, "destinationAdapter should match expected value");
      }

      console2.log("CrossChainForwarder adapters are correct for chainId: %s", chainId);
    }
  }

  function _test_ccr_adapters(
    address _ccrAddress,
    AdaptersConfig[] memory _expectedAdapters
  ) internal {
    ICrossChainReceiver ccr = ICrossChainReceiver(_ccrAddress);

    for (uint256 i = 0; i < _expectedAdapters.length; i++) {
      uint256 chainId = _expectedAdapters[i].chainId;

      address[] memory bridgeAdapters = ccr.getReceiverBridgeAdaptersByChain(chainId);

      assertEq(bridgeAdapters.length, _expectedAdapters[i].adapters.length, "CrossChainReceiver bridge adapters count should match expected value");
      console2.log("CrossChainReceiver adapters: %s", bridgeAdapters.length);
      console2.log("CrossChainReceiver adapters count is correct for chainId: %s", chainId);

      for (uint256 j = 0; j < bridgeAdapters.length; j++) {
        address adapter = bridgeAdapters[j];
        assertEq(adapter, _expectedAdapters[i].adapters[j].localAdapter, "localAdapter should match expected value");
      }

      console2.log("CrossChainReceiver adapters are correct for chainId: %s", chainId);
    }
  }

  function _test_adapter(
    address _adapterAddress,
    string memory _expectedAdapterName,
    address _expectedCrossChainController,
    TrustedRemotesConfig[] memory _trustedRemotes
  ) internal {
    IBaseAdapter adapter = IBaseAdapter(_adapterAddress);

    assertEq(adapter.adapterName(), _expectedAdapterName, "Adapter name should match expected value");
    console2.log("Adapter name is correct");

    IBaseCrossChainController ccc = adapter.CROSS_CHAIN_CONTROLLER();
    assertEq(address(ccc), _expectedCrossChainController, "CrossChainController address should match expected value");
    console2.log("CrossChainController address is correct");

    for (uint256 i = 0; i < _trustedRemotes.length; i++) {
      uint256 chainId = _trustedRemotes[i].chainId;

      address remote = adapter.getTrustedRemoteByChainId(chainId);

      assertEq(remote, _trustedRemotes[i].remoteCrossChainControllerAddress, "Trusted remote address should match expected value");
      console2.log("Trusted remote: %s", remote);
      console2.log("Trusted remote address is correct for chainId: %s", _trustedRemotes[i].chainId);
    }
  }
}
