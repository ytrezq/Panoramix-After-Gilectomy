// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Governed } from "./governance/Governed.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IMoCState {
  function bproUsdPrice() external view returns (uint256);
}

interface AggregatorV2Minimal {
  function latestAnswer() external view returns (int256);
}

/**
 * @title BproUsdAggregatorV2Governed
 * @notice Chainlink V2-only adapter (latestAnswer) with UUPS upgrades governed by Areopagus.
 */
contract BproUsdAggregatorV2Governed is AggregatorV2Minimal, Governed, UUPSUpgradeable {
  using SafeCast for uint256;

  IMoCState public mocState;

  event MoCStateChanged(address indexed previous, address indexed current);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Proxy-style initializer
   * @param _governor Governor address for governance control
   * @param _mocState Address of the IMoCState implementation
   */
  function initialize(address _governor, address _mocState) public initializer {
    require(_governor != address(0), "governor address is zero");
    require(_mocState != address(0), "mocState address is zero");

    __UUPSUpgradeable_init();
    __Governed_init(_governor); // ensure your Governed base exposes this initializer

    mocState = IMoCState(_mocState);
  }

  /**
   * @notice Governance-controlled update of the MoC state contract address.
   * @dev Restricted by Areopagus' onlyAuthorizedChanger.
   */
  function setMoCState(address _mocState) external onlyAuthorizedChanger {
    require(_mocState != address(0), "mocState address is zero");
    emit MoCStateChanged(address(mocState), _mocState);
    mocState = IMoCState(_mocState);
  }

  /**
   * @notice Chainlink V2-only: returns the latest price as int256.
   */
  function latestAnswer() external view returns (int256) {
    return mocState.bproUsdPrice().toInt256();
  }

  /**
   * @dev UUPS authorization hook — REQUIRED.
   * Lock upgrades behind governance (authorized changers).
   */
  function _authorizeUpgrade(address newImplementation) internal override onlyAuthorizedChanger {
    //require(AddressUpgradeable.isContract(newImplementation), "UUPS: not a contract");
  }

  // Reserved storage for future upgrades
  uint256[50] private __gap;
}
