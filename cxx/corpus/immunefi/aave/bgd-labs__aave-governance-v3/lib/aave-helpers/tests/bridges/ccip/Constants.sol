// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Constants {
  // Panic(uint256).selector
  bytes public constant PANIC_SELECTOR =
    hex'4e487b710000000000000000000000000000000000000000000000000000000000000032';

  // All CCIP information is taken from: https://docs.chain.link/ccip/directory/mainnet
  // https://docs.chain.link/ccip/directory/mainnet/chain/mainnet
  uint64 public constant MAINNET_CHAIN_SELECTOR = 5009297550715157269;

  // https://docs.chain.link/ccip/directory/mainnet/chain/ethereum-mainnet-arbitrum-1
  uint64 public constant ARBITRUM_CHAIN_SELECTOR = 4949039107694359620;

  // https://docs.chain.link/ccip/directory/mainnet/chain/ethereum-mainnet-blast-1
  uint64 public constant BLAST_CHAIN_SELECTOR = 4411394078118774322;

  // https://arbiscan.io/address/0x141fa059441E0ca23ce184B6A78bafD2A517DdE8
  address public constant ARBITRUM_ROUTER = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;

  // https://arbiscan.io/address/0xf97f4df75117a78c1A5a0DBb814Af92458539FB4
  address public constant ARBITRUM_LINK = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;

  // https://arbiscan.io/address/0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
  address public constant ARBITRUM_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

  // https://arbiscan.io/address/0x30DeCD269277b8094c00B0bacC3aCaF3fF4Da7fB
  address public constant ARBITRUM_RMN_PROXY = 0x30DeCD269277b8094c00B0bacC3aCaF3fF4Da7fB;

  // https://arbiscan.io/address/0x1f1df9f7fc939E71819F766978d8F900B816761b
  address public constant ARBITRUM_REGISTRY_OWNER = 0x1f1df9f7fc939E71819F766978d8F900B816761b;

  // https://arbiscan.io/address/0x39AE1032cF4B334a1Ed41cdD0833bdD7c7E7751E
  address public constant ARBITRUM_TOKEN_ADMIN = 0x39AE1032cF4B334a1Ed41cdD0833bdD7c7E7751E;

  address public constant CCIP_BNM_ADDRESS = address(0);
  address public constant CCIP_LNM_ADDRESS = address(0);

  // https://etherscan.io/address/0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D
  address public constant MAINNET_ROUTER = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;

  // https://etherscan.io/address/0x514910771AF9Ca656af840dff83E8264EcF986CA
  address public constant MAINNET_LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

  // https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  address public constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  // https://etherscan.io/address/0x411dE17f12D1A34ecC7F45f49844626267c75e81
  address public constant MAINNET_RMN_PROXY = 0x411dE17f12D1A34ecC7F45f49844626267c75e81;

  // https://etherscan.io/address/0x4855174E9479E211337832E109E7721d43A4CA64
  address public constant MAINNET_REGISTRY_OWNER = 0x4855174E9479E211337832E109E7721d43A4CA64;

  // https://etherscan.io/address/0xb22764f98dD05c789929716D677382Df22C05Cb6
  address public constant MAINNET_TOKEN_ADMIN = 0xb22764f98dD05c789929716D677382Df22C05Cb6;
}
