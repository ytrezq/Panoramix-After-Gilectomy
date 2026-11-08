// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceCapAdapterBase
 * @author WOOF!
 * @custom:security-contact dmitriy@woof.software
 * @notice Price adapter to cap the price of the underlying asset.
 */
abstract contract PriceCapAdapterBase {
    /// @notice Event emitted when a new price cap snapshot is set
    event NewPriceCapSnapshot(
        uint256 indexed snapshotRatio,
        uint256 snapshotTimestamp,
        uint256 indexed maxRatioGrowthPerSecond,
        uint32 indexed maxYearlyRatioGrowthPercent
    );

    /// @notice Event emitted when the manager is updated
    event NewManager(address indexed newManager);

    /// @notice Event emitted when the minimum snapshot delay is updated
    event NewMinimumSnapshotDelay(uint256 indexed newMinimumSnapshotDelay);

    /**
     * @notice Price cap snapshot
     * @param snapshotRatio Ratio at the time of snapshot
     * @param snapshotTimestamp Timestamp at the time of snapshot
     * @param maxYearlyRatioGrowthPercent Max yearly growth percent, scaled by BASIS_POINTS
     */
    struct PriceCapSnapshot {
        uint256 snapshotRatio;
        uint48 snapshotTimestamp;
        uint32 maxYearlyRatioGrowthPercent;
    }

    error ManagerIsZeroAddress();
    error SnapshotRatioIsZero();
    error SnapshotCloseToOverflow(uint256 snapshotRatio, uint32 maxYearlyRatioGrowthPercent);
    error InvalidRatioTimestamp(uint48 timestamp);
    error OnlyManager();
    error InvalidInt256();
    error InvalidCheckpointDuration();
    error InvalidAddress();

    /// @notice Modifier to restrict access to the manager
    modifier onlyManager() {
        if (msg.sender != manager) {
            revert OnlyManager();
        }
        _;
    }

    /// @notice Version of the price feed
    uint256 public constant VERSION = 1;

    /// @notice Decimal factor for percentage
    uint256 public constant BASIS_POINTS = 1e4;

    /// @notice Number of seconds per year (365 days)
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Price feed for (ASSET / BASE) pair
    AggregatorV3Interface public immutable assetToBaseAggregator;

    /// @notice Manager address
    address public manager;

    /// @notice Ratio feed for (LST_ASSET / BASE_ASSET) pair
    address public immutable ratioProvider;

    /// @notice Number of decimals in the output of this price feed
    uint8 public immutable decimals;

    /// @notice Minimum time (in seconds) that should have passed from the snapshot timestamp to the current block.timestamp
    uint48 public minimumSnapshotDelay;

    /// @notice Description of the pair
    string public description;

    /// @notice Ratio at the time of snapshot
    uint256 public snapshotRatio;

    /// @notice Timestamp at the time of snapshot
    uint48 public snapshotTimestamp;

    /// @notice Ratio growth per second
    uint256 public maxRatioGrowthPerSecond;

    /// @notice Growth ratio scale
    uint256 public constant GROWTH_RATIO_SCALE = 1e10;

    /// @notice Max yearly growth percent, scaled by BASIS_POINTS
    uint32 public maxYearlyRatioGrowthPercent;

    /// @notice Whether or not the price should be upscaled
    bool internal immutable shouldUpscale;

    /// @notice The amount to upscale or downscale the price by
    int256 internal immutable rescaleFactor;

    /// @notice Timestamp of the last snapshot update
    uint256 public lastSnapshotUpdateTimestamp;

    /**
     * @param _manager Address of the manager
     * @param _baseAggregatorAddress Address of the base aggregator
     * @param _ratioProviderAddress Address of the ratio provider
     * @param _description Description of the pair
     * @param _priceFeedDecimals Number of decimals for the price feed
     * @param _minimumSnapshotDelay Minimum time that should have passed from the snapshot timestamp to the current block.timestamp
     * @param _priceCapSnapshot Parameters to set price cap
     */
    constructor(
        address _manager,
        AggregatorV3Interface _baseAggregatorAddress,
        address _ratioProviderAddress,
        string memory _description,
        uint8 _priceFeedDecimals,
        uint48 _minimumSnapshotDelay,
        PriceCapSnapshot memory _priceCapSnapshot
    ) {
        if (_manager == address(0)) {
            revert ManagerIsZeroAddress();
        }
        if (address(_baseAggregatorAddress) == address(0) || _ratioProviderAddress == address(0)) {
            revert InvalidAddress();
        }
        manager = _manager;
        assetToBaseAggregator = _baseAggregatorAddress;
        ratioProvider = _ratioProviderAddress;
        uint8 underlyingPriceFeedDecimals = assetToBaseAggregator.decimals();
        // Note: Solidity does not allow setting immutables in if/else statements
        shouldUpscale = underlyingPriceFeedDecimals < _priceFeedDecimals ? true : false;
        rescaleFactor = (
            shouldUpscale
                ? _signed256(10 ** (_priceFeedDecimals - underlyingPriceFeedDecimals))
                : _signed256(10 ** (underlyingPriceFeedDecimals - _priceFeedDecimals))
        );
        decimals = _priceFeedDecimals;
        minimumSnapshotDelay = _minimumSnapshotDelay;

        description = _description;

        _setSnapshot(_priceCapSnapshot);
    }

    /**
     * @notice Updates price cap parameters
     * @param priceCapParams Parameters to set price cap
     */
    function updateSnapshot(PriceCapSnapshot memory priceCapParams) external onlyManager {
        _setSnapshot(priceCapParams);
    }

    /**
     * @notice Sets the manager address
     * @param newManager Address of the new manager
     */
    function setManager(address newManager) external onlyManager {
        if (newManager == address(0)) {
            revert ManagerIsZeroAddress();
        }

        manager = newManager;
        emit NewManager(newManager);
    }

    /**
     * @notice Sets the minimum snapshot delay
     * @param newMinimumSnapshotDelay Minimum time that should have passed from the snapshot timestamp to the current block.timestamp
     */
    function setMinimumSnapshotDelay(uint48 newMinimumSnapshotDelay) external onlyManager {
        minimumSnapshotDelay = newMinimumSnapshotDelay;
        emit NewMinimumSnapshotDelay(newMinimumSnapshotDelay);
    }

    /**
     * @notice Price for the latest round
     * @return roundId Round id from the underlying price feed
     * @return answer Latest price for the asset in terms of the underlying asset
     * @return startedAt Timestamp when the round was started; passed on from underlying price feed
     * @return updatedAt Timestamp when the round was last updated; passed on from underlying price feed
     * @return answeredInRound Round id in which the answer was computed; passed on from underlying price feed
     **/
    function latestRoundData()
        external
        view
        virtual
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        int256 currentRatio = getRatio();
        int256 _price;
        (roundId, _price, startedAt, updatedAt, answeredInRound) = assetToBaseAggregator.latestRoundData();

        if (_price <= 0 || currentRatio <= 0) {
            return (roundId, 0, startedAt, updatedAt, answeredInRound);
        }

        int256 maxRatio = _getMaxRatio();

        if (maxRatio < currentRatio) {
            currentRatio = maxRatio;
        }

        answer = _scalePrice((_price * currentRatio) / int256(10 ** ratioDecimals()));
    }

    /**
     * @notice Version of the price feed contract
     * @return The version of the price feed contract
     **/
    function version() external pure returns (uint256) {
        return VERSION;
    }

    /// @notice Returns the current exchange ratio of lst to the underlying(base) asset
    /// @return The current exchange ratio of lst to the underlying asset
    function getRatio() public view virtual returns (int256);

    /// @notice Returns the number of decimals for (lst asset / underlying asset) ratio
    /// @return The number of decimals for (lst asset / underlying asset) ratio
    function ratioDecimals() public view virtual returns (uint8);

    /// @notice Returns if the price is currently capped
    /// @return True if the price is capped, false otherwise
    function isCapped() public view returns (bool) {
        return getRatio() > _getMaxRatio();
    }

    /**
     * @notice Updates price cap parameters from recent snapshot
     * @param priceCapParams Parameters to set price cap
     */
    function _setSnapshot(PriceCapSnapshot memory priceCapParams) internal {
        if (lastSnapshotUpdateTimestamp == block.timestamp) return;
        lastSnapshotUpdateTimestamp = block.timestamp;
        // if snapshot ratio is 0 then growth will not work as expected
        if (priceCapParams.snapshotRatio == 0) {
            revert SnapshotRatioIsZero();
        }

        // new snapshot timestamp should be gt than stored one, but not gt than timestamp of the current block
        //current block timestamp must be at least minimumSnapshotDelay ahead of the stored snapshot timestamp
        if (
            snapshotTimestamp >= priceCapParams.snapshotTimestamp ||
            block.timestamp < snapshotTimestamp + minimumSnapshotDelay ||
            priceCapParams.snapshotTimestamp > block.timestamp
        ) {
            revert InvalidRatioTimestamp(priceCapParams.snapshotTimestamp);
        }

        snapshotRatio = priceCapParams.snapshotRatio;
        snapshotTimestamp = priceCapParams.snapshotTimestamp;
        maxYearlyRatioGrowthPercent = priceCapParams.maxYearlyRatioGrowthPercent;

        uint256 _maxRatioGrowthPerSecond = (uint256(priceCapParams.snapshotRatio) * priceCapParams.maxYearlyRatioGrowthPercent * GROWTH_RATIO_SCALE) /
            BASIS_POINTS /
            SECONDS_PER_YEAR;

        maxRatioGrowthPerSecond = _maxRatioGrowthPerSecond;

        // if the ratio on the current growth speed can overflow less than in a 3 years, revert
        if (snapshotRatio + uint256(_maxRatioGrowthPerSecond * SECONDS_PER_YEAR * 3) / GROWTH_RATIO_SCALE > type(uint128).max) {
            revert SnapshotCloseToOverflow(priceCapParams.snapshotRatio, priceCapParams.maxYearlyRatioGrowthPercent);
        }

        emit NewPriceCapSnapshot(
            priceCapParams.snapshotRatio,
            priceCapParams.snapshotTimestamp,
            _maxRatioGrowthPerSecond,
            priceCapParams.maxYearlyRatioGrowthPercent
        );
    }

    /**
     * @notice Scales the price based on the rescale factor
     * @param price Price to scale
     * @return scaled Price
     */
    function _scalePrice(int256 price) internal view returns (int256) {
        int256 scaledPrice;
        if (shouldUpscale) {
            scaledPrice = price * rescaleFactor;
        } else {
            scaledPrice = price / rescaleFactor;
        }
        return scaledPrice;
    }

    /// @notice Returns the maximum ratio that can be achieved at the current block.timestamp
    function _getMaxRatio() internal view returns (int256) {
        return int256(snapshotRatio + (maxRatioGrowthPerSecond * (block.timestamp - snapshotTimestamp)) / GROWTH_RATIO_SCALE);
    }

    function _signed256(uint256 n) internal pure returns (int256) {
        if (n > uint256(type(int256).max)) revert InvalidInt256();
        return int256(n);
    }
}
