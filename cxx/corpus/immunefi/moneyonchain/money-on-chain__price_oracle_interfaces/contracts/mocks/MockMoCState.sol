// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../interfaces/IMocState.sol";

contract MockMoCState is IMocState {
  uint256 private _bproUsdPrice;
  address private _btcProvider;
  uint256 private _bucketNBTC;
  uint256 private _bucketNDoc;

  constructor(uint256 initialBproUsdPrice, address initialBtcProvider) {
    _bproUsdPrice = initialBproUsdPrice;
    _btcProvider = initialBtcProvider;
    _bucketNBTC = 5e18;
    _bucketNDoc = initialBproUsdPrice;
  }

  function setBproUsdPrice(uint256 newPrice) external {
    _bproUsdPrice = newPrice;
  }

  function setBtcPriceProvider(address newProvider) external {
    _btcProvider = newProvider;
  }

  function setBucketNBTC(uint256 newValue) external {
    _bucketNBTC = newValue;
  }

  function setBucketNDoc(uint256 newValue) external {
    _bucketNDoc = newValue;
  }

  function bproUsdPrice() external view returns (uint256) {
    return _bproUsdPrice;
  }

  function bproTecPrice() external pure returns (uint256) {
    return 1e18; // To keep calculations, 1BTC is 1BPRO
  }

  function getProtected() external pure returns (uint256) {
    return 2e18;
  }

  function getBtcPriceProvider() external view returns (address) {
    return _btcProvider;
  }

  function docTotalSupply() external view returns (uint256) {
    return _bproUsdPrice; // Exactly 1 BTC worth of DOC at current price.
  }

  function getInrateBag(bytes32 /*bucket*/) external pure returns (uint256) {
    return 0; // No inrate BTC
  }

  function rbtcInSystem() external pure returns (uint256) {
    return 5e18; // 5BTC total backing.
  }

  function getBucketNBTC(bytes32 /*bucket*/) external view returns (uint256) {
    return _bucketNBTC; // configurable for tests.
  }

  function getBucketNBPro(bytes32 /*bucket*/) external pure returns (uint256) {
    return 4e18; // 4BPRO, which equals 4BTC at current 1:1 rate.
  }

  function getBucketNDoc(bytes32 /*bucket*/) external view returns (uint256) {
    return _bucketNDoc; // configurable for tests.
  }

  function peg() external pure returns (uint256) {
    return 1; // Peg is 1 on MOC. (not 1e18, just 1).
  }

  function state() external pure returns (States) {
    return States.AboveCobj;
  }
}
