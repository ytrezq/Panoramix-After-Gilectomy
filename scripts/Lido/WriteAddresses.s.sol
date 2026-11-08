// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import './BaseScript.sol';

contract WriteDeployedAddresses is Script {
  using stdJson for string;

  function run() public {
    Network[] memory networks = new Network[](2);
    // mainnets
     networks[0] = Network({
       path: DeployerHelpers.getPathByChainId(ChainIds.ETHEREUM, false),
       name: 'ethereum'
     });
     networks[1] = Network({
       path: DeployerHelpers.getPathByChainId(ChainIds.BNB, false),
       name: 'binance'
     });

    // testnets
    // networks[0] = Network({
    //   path: DeployerHelpers.getPathByChainId(TestNetChainIds.ETHEREUM_SEPOLIA, false),
    //   name: 'sepolia'
    // });
    // networks[1] = Network({
    //   path: DeployerHelpers.getPathByChainId(TestNetChainIds.POLYGON_MUMBAI, false),
    //   name: 'mumbai'
    // });
    // networks[2] = Network({
    //   path: DeployerHelpers.getPathByChainId(TestNetChainIds.BNB_TESTNET, false),
    //   name: 'bnbTestnet'
    // });

    // local forks
    // networks[3] = Network({
    //   path: DeployerHelpers.getPathByChainId(ChainIds.ETHEREUM, true),
    //   name: 'mainnet-fork'
    // });
    // networks[4] = Network({
    //   path: DeployerHelpers.getPathByChainId(ChainIds.POLYGON, true),
    //   name: 'polygon-fork'
    // });
    // networks[5] = Network({
    //   path: DeployerHelpers.getPathByChainId(ChainIds.BNB, true),
    //   name: 'binance-fork'
    // });

    string memory deployedJson = 'deployments';

    for (uint256 i = 0; i < networks.length; i++) {
      DeployerHelpers.Addresses memory addresses = DeployerHelpers.decodeJson(networks[i].path, vm);
      string memory json = networks[i].name;

      json.serialize('chainId', addresses.chainId);
      json.serialize('proxyAdmin', addresses.proxyAdmin);
      json.serialize('crossChainController', addresses.crossChainController);
      json.serialize('crossChainControllerImpl', addresses.crossChainControllerImpl);
      json.serialize('executorMock', addresses.executorMock);
      json.serialize('executorProd', addresses.executorProd);
      json.serialize('guardian', addresses.guardian);
      json.serialize('ccipAdapter', addresses.ccipAdapter);
      json.serialize('hlAdapter', addresses.hlAdapter);
      json.serialize('lzAdapter', addresses.lzAdapter);
      json.serialize('wormholeAdapter', addresses.wormholeAdapter);
      json = json.serialize('mockDestination', addresses.mockDestination);

      if (i == networks.length - 1) {
        deployedJson = deployedJson.serialize(networks[i].name, json);
      } else {
        deployedJson.serialize(networks[i].name, json);
      }
    }

    vm.writeJson(deployedJson, './deployments/addresses.json');
  }
}
