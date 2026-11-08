pragma solidity ^0.8.19;

import 'forge-std/console2.sol';
import 'forge-std/Vm.sol';

import {ChainIds} from "../../../src/contracts/libs/ChainIds.sol";

import {BaseStateTest} from "./BaseStateTest.sol";

contract CrossChainControllerStateTest is BaseStateTest {

  address public proxyAdmin;
  address public cccAddress;
  address public cccImplAddress;

  address public DAO_AGENT;

  function setUp() override public {
    super.setUp();

    vm.selectFork(bnbFork);

    proxyAdmin = address(crossChainAddresses.bnb.proxyAdmin);
    cccAddress = address(crossChainAddresses.bnb.crossChainController);
    cccImplAddress = address(crossChainAddresses.bnb.crossChainControllerImpl);


    DAO_AGENT = crossChainAddresses.bnb.executorMock;
    if (isRealDaoAgent) {
      DAO_AGENT = crossChainAddresses.bnb.executorProd;
    }

    console2.log("Binance DAO Agent (CrossChainExecutor): %s", DAO_AGENT);
  }

  function test_CorrectFork() public {
    _test_fork(bnbFork, "Binance");
  }

  function test_ProxyAdminState() public {
    _test_proxy_admin(proxyAdmin, cccAddress, cccImplAddress, DAO_AGENT);
  }

  function test_CrossChainControllerState() public {
    _test_ccc_owners(cccAddress, DAO_AGENT);
    _test_ccc_funds(cccAddress, 1e16);
  }

  function test_CrossChainController_ForwarderAdaptersState() public {
    AdaptersConfig[] memory ccfAdaptersLists = new AdaptersConfig[](1);

    ccfAdaptersLists[0].chainId = ChainIds.ETHEREUM;
    ccfAdaptersLists[0].adapters = new AdapterLink[](0);

    _test_ccf_adapters(
      cccAddress,
      ccfAdaptersLists
    );
  }

  function test_CrossChainController_ReceiverAdaptersState() public {
    AdaptersConfig[] memory ccrAdaptersLists = new AdaptersConfig[](1);

    ccrAdaptersLists[0].chainId = ChainIds.ETHEREUM;
    ccrAdaptersLists[0].adapters = new AdapterLink[](4);

    ccrAdaptersLists[0].adapters[0].localAdapter = address(crossChainAddresses.bnb.ccipAdapter);
    ccrAdaptersLists[0].adapters[0].destinationAdapter = address(crossChainAddresses.eth.ccipAdapter);
    ccrAdaptersLists[0].adapters[1].localAdapter = address(crossChainAddresses.bnb.lzAdapter);
    ccrAdaptersLists[0].adapters[1].destinationAdapter = address(crossChainAddresses.eth.lzAdapter);
    ccrAdaptersLists[0].adapters[2].localAdapter = address(crossChainAddresses.bnb.hlAdapter);
    ccrAdaptersLists[0].adapters[2].destinationAdapter = address(crossChainAddresses.eth.hlAdapter);
    ccrAdaptersLists[0].adapters[3].localAdapter = address(crossChainAddresses.bnb.wormholeAdapter);
    ccrAdaptersLists[0].adapters[3].destinationAdapter = address(crossChainAddresses.eth.wormholeAdapter);

    _test_ccr_adapters(
      cccAddress,
      ccrAdaptersLists
    );
  }

  function test_CrossChainControllerImplState() public {
    _test_ccc_impl(cccImplAddress);
  }

  function test_ccipAdapter() public {
    TrustedRemotesConfig[] memory trustedRemotes = new TrustedRemotesConfig[](1);

    trustedRemotes[0].chainId = ChainIds.ETHEREUM;
    trustedRemotes[0].remoteCrossChainControllerAddress = address(crossChainAddresses.eth.crossChainController);

    _test_adapter(
      address(crossChainAddresses.bnb.ccipAdapter),
      'CCIP adapter',
      cccAddress,
      trustedRemotes
    );
  }

  function test_lzAdapter() public {
    TrustedRemotesConfig[] memory trustedRemotes = new TrustedRemotesConfig[](1);

    trustedRemotes[0].chainId = ChainIds.ETHEREUM;
    trustedRemotes[0].remoteCrossChainControllerAddress = address(crossChainAddresses.eth.crossChainController);

    _test_adapter(
      address(crossChainAddresses.bnb.lzAdapter),
      'LayerZero adapter',
      cccAddress,
      trustedRemotes
    );
  }

  function test_hlAdapter() public {
    TrustedRemotesConfig[] memory trustedRemotes = new TrustedRemotesConfig[](1);

    trustedRemotes[0].chainId = ChainIds.ETHEREUM;
    trustedRemotes[0].remoteCrossChainControllerAddress = address(crossChainAddresses.eth.crossChainController);

    _test_adapter(
      address(crossChainAddresses.bnb.hlAdapter),
      'Hyperlane adapter',
      cccAddress,
      trustedRemotes
    );
  }

  function test_wormholeAdapter() public {
    TrustedRemotesConfig[] memory trustedRemotes = new TrustedRemotesConfig[](1);

    trustedRemotes[0].chainId = ChainIds.ETHEREUM;
    trustedRemotes[0].remoteCrossChainControllerAddress = address(crossChainAddresses.eth.crossChainController);

    _test_adapter(
      address(crossChainAddresses.bnb.wormholeAdapter),
      'Wormhole adapter',
      cccAddress,
      trustedRemotes
    );
  }
}
