// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract MockPriceProviderInfo {
  uint256 internal _price;
  bool internal _valid;
  uint256 internal _lastPublicationBlock;

  constructor(uint256 price_, bool valid_, uint256 lastPublicationBlock_) {
    _price = price_;
    _valid = valid_;
    _lastPublicationBlock = lastPublicationBlock_;
  }

  function setPriceInfo(uint256 price_, bool valid_, uint256 lastPublicationBlock_) external {
    _price = price_;
    _valid = valid_;
    _lastPublicationBlock = lastPublicationBlock_;
  }

  function peek() external view virtual returns (bytes32, bool) {
    revert("Address is not whitelisted");
  }

  function getPriceInfo()
    external
    view
    returns (uint256 price, bool valid, uint256 lastPublicationBlock)
  {
    return (_price, _valid, _lastPublicationBlock);
  }

  function getLastPublicationBlock() external view returns (uint256) {
    return _lastPublicationBlock;
  }
}

contract MockPublicPriceProviderInfo is MockPriceProviderInfo {
  constructor(
    uint256 price_,
    bool valid_,
    uint256 lastPublicationBlock_
  ) MockPriceProviderInfo(price_, valid_, lastPublicationBlock_) {}

  function peek() external view override returns (bytes32, bool) {
    return (bytes32(_price), _valid);
  }
}

contract MockMocBucket {
  address[] private _priceProviders;
  uint256 private _coverage;
  uint256[] private _expectedPrices;
  bool private _revertOnCoverage;

  constructor(address[] memory priceProviders_) {
    _priceProviders = priceProviders_;
  }

  function setPriceProvider(uint256 index, address priceProvider) external {
    _priceProviders[index] = priceProvider;
  }

  function setCoverage(uint256 coverage_) external {
    _coverage = coverage_;
  }

  function setExpectedPrices(uint256[] calldata prices) external {
    _expectedPrices = prices;
  }

  function setRevertOnCoverage(bool enabled) external {
    _revertOnCoverage = enabled;
  }

  function calcCglb(uint256[] calldata prices) external view returns (uint256) {
    require(!_revertOnCoverage, "unexpected bucket coverage call");
    require(
      keccak256(abi.encode(prices)) == keccak256(abi.encode(_expectedPrices)),
      "wrong bucket prices"
    );
    return _coverage;
  }

  function getTpAmount() external view returns (uint256) {
    return _priceProviders.length;
  }

  function pegContainer(uint256 index) external view returns (uint256 nTP, address priceProvider) {
    return (0, _priceProviders[index]);
  }
}

contract MockMocMultiCollateralGuard {
  bool private _revertOnCalculation;
  uint256 private _combinedCoverage;
  address[] private _buckets;
  uint256[][] private _expectedPrices;

  constructor(uint256 combinedCoverage_, uint256, uint256) {
    _combinedCoverage = combinedCoverage_;
  }

  function setCombinedCoverage(uint256 combinedCoverage_) external {
    _combinedCoverage = combinedCoverage_;
  }

  function setRevertOnCalculation(bool enabled) external {
    _revertOnCalculation = enabled;
  }

  function addBucket(address bucket) external {
    _buckets.push(bucket);
    _expectedPrices.push();
  }

  function setExpectedComponentPrice(
    uint256 bucketIndex,
    uint256 tpIndex,
    uint256 expectedComponentPrice
  ) external {
    while (_expectedPrices[bucketIndex].length <= tpIndex) {
      _expectedPrices[bucketIndex].push();
    }
    _expectedPrices[bucketIndex][tpIndex] = expectedComponentPrice;
  }

  function getBucketAmount() external view returns (uint256) {
    return _buckets.length;
  }

  function buckets(uint256 index) external view returns (address) {
    return _buckets[index];
  }

  function calcCombinedCglbWithPrices(
    uint256[][] calldata bucketsPACtps
  ) external view returns (uint256 combinedCglb) {
    require(!_revertOnCalculation, "unexpected guard calculation");
    require(bucketsPACtps.length == _buckets.length, "wrong bucket count");
    for (uint256 j = 0; j < bucketsPACtps.length; j++) {
      require(bucketsPACtps[j].length == _expectedPrices[j].length, "wrong TP count");
      for (uint256 i = 0; i < bucketsPACtps[j].length; i++) {
        uint256 expectedPrice = _expectedPrices[j][i];
        if (expectedPrice != 0) {
          require(bucketsPACtps[j][i] == expectedPrice, "wrong component price");
        }
      }
    }
    return _combinedCoverage;
  }
}
