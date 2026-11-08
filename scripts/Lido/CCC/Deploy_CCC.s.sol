// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ProxyAdmin} from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import {CrossChainController, ICrossChainController} from '../../../src/contracts/CrossChainController.sol';

import '../BaseScript.sol';

interface OwnableWithGuardian {
  function updateGuardian(address guardian) external;
}

abstract contract BaseCCCNetworkDeployment is BaseScript {

  event ProxyCreated(address proxy, address indexed logic, address indexed admin);
  event ProxyAdminCreated(address proxyAdmin, address indexed adminOwner);

  event CCCCreated(address indexed ccc);
  event CCCImplementationPetrified(address indexed cccImpl);

  function _execute(DeployerHelpers.Addresses memory addresses) internal override {
    // Create a new ProxyAdmin for the CrossChainController proxy

    address proxyAdmin = address(new ProxyAdmin());

    emit ProxyAdminCreated(proxyAdmin, msg.sender);

    addresses.proxyAdmin = proxyAdmin;

    // Create a new CrossChainController implementation

    ICrossChainController crossChainControllerImpl = new CrossChainController();

    addresses.crossChainControllerImpl = address(crossChainControllerImpl);

    emit CCCCreated(address(crossChainControllerImpl));

    // Create a new TransparentUpgradeableProxy for the CrossChainController implementation
    address proxy = address(new TransparentUpgradeableProxy(
      addresses.crossChainControllerImpl,
      addresses.proxyAdmin,
      abi.encodeWithSelector(
        CrossChainController.initialize.selector,
        msg.sender,
        Constants.ZERO,
        new ICrossChainController.ConfirmationInput[](0),
        new ICrossChainController.ReceiverBridgeAdapterConfigInput[](0),
        new ICrossChainController.ForwarderBridgeAdapterConfigInput[](0),
        new address[](0)
      )
    ));

    emit ProxyCreated(proxy, address(crossChainControllerImpl), proxyAdmin);

    // Petrify the implementation
    Ownable(addresses.crossChainControllerImpl).transferOwnership(Constants.DEAD);
    OwnableWithGuardian(addresses.crossChainControllerImpl).updateGuardian(Constants.ZERO);

    emit CCCImplementationPetrified(addresses.crossChainControllerImpl);

    addresses.crossChainController = proxy;
  }
}

contract Ethereum is BaseCCCNetworkDeployment {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return ChainIds.ETHEREUM;
  }
}

contract Ethereum_testnet is BaseCCCNetworkDeployment {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return TestNetChainIds.ETHEREUM_SEPOLIA;
  }
}

contract Ethereum_local is Ethereum {
  function isLocalFork() public pure override returns (bool) {
    return true;
  }
}

contract Binance is BaseCCCNetworkDeployment {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return ChainIds.BNB;
  }
}

contract Binance_testnet is BaseCCCNetworkDeployment {
  function TRANSACTION_NETWORK() public pure override returns (uint256) {
    return TestNetChainIds.BNB_TESTNET;
  }
}

contract Binance_local is Binance {
  function isLocalFork() public pure override returns (bool) {
    return true;
  }
}
