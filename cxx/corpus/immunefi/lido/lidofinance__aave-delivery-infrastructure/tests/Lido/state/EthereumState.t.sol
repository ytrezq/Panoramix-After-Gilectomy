pragma solidity ^0.8.19;

import 'forge-std/console2.sol';
import 'forge-std/Vm.sol';

import {ChainIds} from "../../../src/contracts/libs/ChainIds.sol";

import {BaseStateTest} from "./BaseStateTest.sol";

contract EthereumStateTest is BaseStateTest {

  address public proxyAdmin;
  address public cccAddress;
  address public cccImplAddress;

  address public DAO_AGENT;

  function setUp() override public {
    super.setUp();

    vm.selectFork(ethFork);

    proxyAdmin = address(crossChainAddresses.eth.proxyAdmin);
    cccAddress = address(crossChainAddresses.eth.crossChainController);
    cccImplAddress = address(crossChainAddresses.eth.crossChainControllerImpl);

    DAO_AGENT = LIDO_DAO_AGENT_FAKE;
    if (isRealDaoAgent) {
      DAO_AGENT = LIDO_DAO_AGENT;
    }

    console2.log("Ethereum DAO Agent: %s", DAO_AGENT);
  }

  function test_CorrectFork() public {
    _test_fork(ethFork, "Ethereum");
  }

  function test_ProxyAdminState() public {
    _test_proxy_admin(proxyAdmin, cccAddress, cccImplAddress, DAO_AGENT);
  }

  function test_CrossChainControllerState() public {
    _test_ccc_owners(cccAddress, DAO_AGENT);
    _test_ccc_funds(cccAddress, 5e17); // 0.5 ETH
  }

  function test_CrossChainController_ForwarderAdaptersState() public {
    AdaptersConfig[] memory ccfAdaptersLists = new AdaptersConfig[](2);

    ccfAdaptersLists[1].chainId = ChainIds.BNB;
    ccfAdaptersLists[1].adapters = new AdapterLink[](4);
    ccfAdaptersLists[1].adapters[0].localAdapter = address(crossChainAddresses.eth.ccipAdapter);
    ccfAdaptersLists[1].adapters[0].destinationAdapter = address(crossChainAddresses.bnb.ccipAdapter);
    ccfAdaptersLists[1].adapters[1].localAdapter = address(crossChainAddresses.eth.lzAdapter);
    ccfAdaptersLists[1].adapters[1].destinationAdapter = address(crossChainAddresses.bnb.lzAdapter);
    ccfAdaptersLists[1].adapters[2].localAdapter = address(crossChainAddresses.eth.hlAdapter);
    ccfAdaptersLists[1].adapters[2].destinationAdapter = address(crossChainAddresses.bnb.hlAdapter);
    ccfAdaptersLists[1].adapters[3].localAdapter = address(crossChainAddresses.eth.wormholeAdapter);
    ccfAdaptersLists[1].adapters[3].destinationAdapter = address(crossChainAddresses.bnb.wormholeAdapter);

    _test_ccf_adapters(
      cccAddress,
      ccfAdaptersLists
    );
  }

  function test_CrossChainController_ReceiverAdaptersState() public {
    AdaptersConfig[] memory ccrAdaptersLists = new AdaptersConfig[](1);

    ccrAdaptersLists[0].chainId = ChainIds.BNB;
    ccrAdaptersLists[0].adapters = new AdapterLink[](0);

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

    trustedRemotes[0].chainId = ChainIds.BNB;
    trustedRemotes[0].remoteCrossChainControllerAddress = ZERO_ADDRESS;

    _test_adapter(
      address(crossChainAddresses.eth.ccipAdapter),
      'CCIP adapter',
      cccAddress,
      trustedRemotes
    );
  }

  function test_lzAdapter() public {
    TrustedRemotesConfig[] memory trustedRemotes = new TrustedRemotesConfig[](1);

    trustedRemotes[0].chainId = ChainIds.BNB;
    trustedRemotes[0].remoteCrossChainControllerAddress = ZERO_ADDRESS;

    _test_adapter(
      address(crossChainAddresses.eth.lzAdapter),
      'LayerZero adapter',
      cccAddress,
      trustedRemotes
    );
  }

  function test_hlAdapter() public {
    TrustedRemotesConfig[] memory trustedRemotes = new TrustedRemotesConfig[](1);

    trustedRemotes[0].chainId = ChainIds.BNB;
    trustedRemotes[0].remoteCrossChainControllerAddress = ZERO_ADDRESS;

    _test_adapter(
      address(crossChainAddresses.eth.hlAdapter),
      'Hyperlane adapter',
      cccAddress,
      trustedRemotes
    );
  }

  function test_wormholeAdapter() public {
    TrustedRemotesConfig[] memory trustedRemotes = new TrustedRemotesConfig[](1);

    trustedRemotes[0].chainId = ChainIds.BNB;
    trustedRemotes[0].remoteCrossChainControllerAddress = ZERO_ADDRESS;

    _test_adapter(
      address(crossChainAddresses.eth.wormholeAdapter),
      'Wormhole adapter',
      cccAddress,
      trustedRemotes
    );
  }
}
