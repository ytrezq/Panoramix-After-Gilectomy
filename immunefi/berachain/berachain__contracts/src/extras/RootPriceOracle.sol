// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IPriceOracle } from "./IPriceOracle.sol";
import { IRootPriceOracle } from "./IRootPriceOracle.sol";
import { Utils } from "../libraries/Utils.sol";

/// @title Root price oracle
/// @dev Combines spot and pyth price oracles, to provide a price source derived
/// from comparing prices of both oracles.
contract RootPriceOracle is AccessControl, Initializable, IRootPriceOracle {
    using Utils for bytes4;

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 internal constant WAD = 1 ether;

    /// @notice spot price oracle of BEX pool
    IPriceOracle public spotOracle;
    /// @notice pyth price oracle
    IPriceOracle public pythOracle;

    /// @dev do not use constructor in order to predict the contract address
    function initialize(address initialAdmin) external initializer {
        if (initialAdmin == address(0)) ZeroAddress.selector.revertWith();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
    }

    /// @notice Sets the spot oracle.
    /// @param spotOracle_ The new address of the spot oracle.
    function setSpotOracle(address spotOracle_) external onlyRole(MANAGER_ROLE) {
        if (spotOracle_ == address(0)) ZeroAddress.selector.revertWith();

        spotOracle = IPriceOracle(spotOracle_);

        emit SpotOracleSet(spotOracle_);
    }

    /// @notice Sets the pyth oracle.
    /// @param pythOracle_ The new address of the pyth oracle.
    function setPythOracle(address pythOracle_) external onlyRole(MANAGER_ROLE) {
        if (pythOracle_ == address(0)) ZeroAddress.selector.revertWith();

        pythOracle = IPriceOracle(pythOracle_);

        emit PythOracleSet(pythOracle_);
    }

    /// @inheritdoc IPriceOracle
    /// @dev selects the data which has the largest price deviation from ONE (WAD) if data from both oracles is
    /// available
    /// @dev if only pyth is available, it returns the data from the pyth price oracle
    /// @dev if only spot is available, revert
    function getPrice(address asset) external view returns (Data memory data) {
        (bool pythAvailable, bool spotAvailable) = _getAssetAvailability(asset);

        if (!pythAvailable) {
            UnreliablePrice.selector.revertWith();
        }

        if (!spotAvailable) {
            return pythOracle.getPrice(asset);
        }

        return _selectLargestDeviation(pythOracle.getPrice(asset), spotOracle.getPrice(asset));
    }

    /// @inheritdoc IPriceOracle
    /// @dev selects the data which has the largest price deviation from ONE (WAD) if data from both oracles is
    /// available
    /// @dev if only pyth is available, it returns the data from the pyth price oracle
    /// @dev if only spot is available, revert
    function getPriceUnsafe(address asset) external view returns (Data memory data) {
        (bool pythAvailable, bool spotAvailable) = _getAssetAvailability(asset);

        if (!pythAvailable) {
            UnreliablePrice.selector.revertWith();
        }

        if (!spotAvailable) {
            return pythOracle.getPriceUnsafe(asset);
        }

        return _selectLargestDeviation(pythOracle.getPriceUnsafe(asset), spotOracle.getPriceUnsafe(asset));
    }

    /// @inheritdoc IPriceOracle
    // @dev selects the data which has the largest price deviation from ONE (WAD) if data from both oracles is
    // available
    /// @dev if only pyth is available, it returns the data from the pyth price oracle
    /// @dev if only spot is available, revert
    function getPriceNoOlderThan(address asset, uint256 age) external view returns (Data memory data) {
        (bool pythAvailable, bool spotAvailable) = _getAssetAvailability(asset);

        if (!pythAvailable) {
            UnreliablePrice.selector.revertWith();
        }

        if (!spotAvailable) {
            return pythOracle.getPriceNoOlderThan(asset, age);
        }

        return _selectLargestDeviation(
            pythOracle.getPriceNoOlderThan(asset, age), spotOracle.getPriceNoOlderThan(asset, age)
        );
    }

    /// @inheritdoc IPriceOracle
    function priceAvailable(address asset) external view returns (bool availability) {
        if (address(pythOracle) != address(0)) {
            availability = pythOracle.priceAvailable(asset);
        }
    }

    /// @notice checks if the asset is available in the spot and pyth price oracle
    /// @param asset the asset to check
    /// @return pythAvailable true if the asset is available in the pyth price oracle, false otherwise
    /// @return spotAvailable true if the asset is available in the spot price oracle, false otherwise
    function _getAssetAvailability(address asset) internal view returns (bool pythAvailable, bool spotAvailable) {
        if (address(pythOracle) != address(0)) {
            pythAvailable = pythOracle.priceAvailable(asset);
        }
        if (address(spotOracle) != address(0)) {
            spotAvailable = spotOracle.priceAvailable(asset);
        }
    }

    /// @notice selects the data which has the largest price deviation from ONE (WAD)
    /// @param pythData the data from the pyth price oracle
    /// @param spotData the data from the spot price oracle
    /// @return data the data with the largest price deviation from ONE (WAD)
    function _selectLargestDeviation(
        Data memory pythData,
        Data memory spotData
    )
        internal
        pure
        returns (Data memory data)
    {
        if (spotData.price > WAD) {
            spotData.price = WAD;
        }

        uint256 absSpotDeviation = spotData.price >= WAD ? spotData.price - WAD : WAD - spotData.price;
        uint256 absPythDeviation = pythData.price >= WAD ? pythData.price - WAD : WAD - pythData.price;

        data = absSpotDeviation > absPythDeviation ? spotData : pythData;
    }
}
