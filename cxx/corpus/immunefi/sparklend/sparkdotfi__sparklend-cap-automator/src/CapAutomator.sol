// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

import { AccessControlEnumerable } from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { ReserveConfiguration } from "../lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "../lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import { WadRayMath }           from "../lib/aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol";

import { ICapAutomator } from "./interfaces/ICapAutomator.sol";
import { IERC20Like }    from "./interfaces/Common.sol";

import {
    IPoolAddressesProviderLike,
    IPoolConfiguratorLike,
    IPoolLike,
    IScaledBalanceTokenLike
} from "./interfaces/IAAVEV3.sol";

contract CapAutomator is ICapAutomator, AccessControlEnumerable {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath           for uint256;

    /**********************************************************************************************/
    /*** Declarations and Constructor                                                           ***/
    /**********************************************************************************************/

    struct CapConfig {
        uint48 max;              // Full tokens
        uint48 gap;              // Full tokens
        uint48 increaseCooldown; // Seconds
        uint48 lastUpdateBlock;  // Blocks
        uint48 lastIncreaseTime; // Seconds
    }

    bytes32 public constant UPDATE_ROLE = keccak256("UPDATE_ROLE");

    address public immutable poolConfigurator;
    address public immutable pool;

    mapping(address => CapConfig) public supplyCapConfigs;
    mapping(address => CapConfig) public borrowCapConfigs;

    constructor(address poolAddressesProvider, address admin, address updater)  {
        require(admin   != address(0), "CapAutomator/invalid-admin-address");
        require(updater != address(0), "CapAutomator/invalid-updater-address");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPDATE_ROLE,        updater);

        pool             = IPoolAddressesProviderLike(poolAddressesProvider).getPool();
        poolConfigurator = IPoolAddressesProviderLike(poolAddressesProvider).getPoolConfigurator();
    }

    /**********************************************************************************************/
    /*** Admin Functions                                                                        ***/
    /**********************************************************************************************/

    function setSupplyCapConfig(
        address asset,
        uint256 max,
        uint256 gap,
        uint256 increaseCooldown
    )
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(max > 0,                                          "CapAutomator/zero-cap");
        require(gap > 0,                                          "CapAutomator/zero-gap");
        require(max <= ReserveConfiguration.MAX_VALID_SUPPLY_CAP, "CapAutomator/invalid-cap");
        require(gap <= max,                                       "CapAutomator/invalid-gap");

        supplyCapConfigs[asset] = CapConfig(
            uint48(max),
            uint48(gap),
            _uint48(increaseCooldown),
            supplyCapConfigs[asset].lastUpdateBlock,
            supplyCapConfigs[asset].lastIncreaseTime
        );

        emit SetSupplyCapConfig(asset, max, gap, increaseCooldown);
    }

    function setBorrowCapConfig(
        address asset,
        uint256 max,
        uint256 gap,
        uint256 increaseCooldown
    )
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(max > 0,                                          "CapAutomator/zero-cap");
        require(gap > 0,                                          "CapAutomator/zero-gap");
        require(max <= ReserveConfiguration.MAX_VALID_BORROW_CAP, "CapAutomator/invalid-cap");
        require(gap <= max,                                       "CapAutomator/invalid-gap");

        borrowCapConfigs[asset] = CapConfig(
            uint48(max),
            uint48(gap),
            _uint48(increaseCooldown),
            borrowCapConfigs[asset].lastUpdateBlock,
            borrowCapConfigs[asset].lastIncreaseTime
        );

        emit SetBorrowCapConfig(asset, max, gap, increaseCooldown);
    }

    function removeSupplyCapConfig(address asset) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(supplyCapConfigs[asset].max > 0, "CapAutomator/nonexistent-config");

        delete supplyCapConfigs[asset];

        emit RemoveSupplyCapConfig(asset);
    }

    function removeBorrowCapConfig(address asset) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(borrowCapConfigs[asset].max > 0, "CapAutomator/nonexistent-config");

        delete borrowCapConfigs[asset];

        emit RemoveBorrowCapConfig(asset);
    }

    /**********************************************************************************************/
    /*** Updater Functions                                                                      ***/
    /**********************************************************************************************/

    function execSupply(address asset) external override onlyRole(UPDATE_ROLE) returns (uint256) {
        return _updateSupplyCap(asset);
    }

    function execBorrow(address asset) external override onlyRole(UPDATE_ROLE) returns (uint256) {
        return _updateBorrowCap(asset);
    }

    function exec(address asset)
        external
        override
        onlyRole(UPDATE_ROLE)
        returns (uint256 newSupplyCap, uint256 newBorrowCap)
    {
        newSupplyCap = _updateSupplyCap(asset);
        newBorrowCap = _updateBorrowCap(asset);
    }

    /**********************************************************************************************/
    /*** Internal Functions                                                                     ***/
    /**********************************************************************************************/

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    function _uint48(uint256 _input) internal pure returns (uint48 _output) {
        require(_input <= type(uint48).max, "CapAutomator/uint48-cast");
        _output = uint48(_input);
    }

    function _calculateNewCap(
        CapConfig memory capConfig,
        uint256 currentValue,
        uint256 currentCap
    ) internal view returns (uint256) {
        uint256 max = capConfig.max;

        if (max == 0 || capConfig.lastUpdateBlock == block.number) return currentCap;

        uint256 newCap = _min(currentValue + capConfig.gap, max);

        // Cap cannot be increased before cooldown passes, but can be decreased
        if (
            newCap > currentCap
            && block.timestamp < (capConfig.lastIncreaseTime + capConfig.increaseCooldown)
        ) return currentCap;

        return newCap;
    }

    function _updateSupplyCap(address asset) internal returns (uint256) {
        DataTypes.ReserveData memory reserveData = IPoolLike(pool).getReserveData(asset);
        CapConfig             memory capConfig   = supplyCapConfigs[asset];

        uint256 currentSupplyCap = reserveData.configuration.getSupplyCap();

        uint256 currentSupply = (
                IScaledBalanceTokenLike(reserveData.aTokenAddress).scaledTotalSupply()
                + uint256(reserveData.accruedToTreasury)
            ).rayMul(reserveData.liquidityIndex)
            / 10 ** reserveData.configuration.getDecimals();

        uint256 newSupplyCap = _calculateNewCap(
            capConfig,
            currentSupply,
            currentSupplyCap
        );

        if (newSupplyCap == currentSupplyCap) return currentSupplyCap;

        if (newSupplyCap > currentSupplyCap) {
            capConfig.lastIncreaseTime = _uint48(block.timestamp);
        }

        capConfig.lastUpdateBlock = _uint48(block.number);

        supplyCapConfigs[asset] = capConfig;

        IPoolConfiguratorLike(poolConfigurator).setSupplyCap(asset, newSupplyCap);

        emit UpdateSupplyCap(asset, currentSupplyCap, newSupplyCap);

        return newSupplyCap;
    }

    function _updateBorrowCap(address asset) internal returns (uint256) {
        DataTypes.ReserveData memory reserveData = IPoolLike(pool).getReserveData(asset);
        CapConfig             memory capConfig   = borrowCapConfigs[asset];

        uint256 currentBorrowCap = reserveData.configuration.getBorrowCap();

        // `stableDebt` is not in use and is always 0
        uint256 currentBorrow =
            IERC20Like(reserveData.variableDebtTokenAddress).totalSupply()
            / 10 ** reserveData.configuration.getDecimals();

        uint256 newBorrowCap = _calculateNewCap(
            capConfig,
            currentBorrow,
            currentBorrowCap
        );

        if (newBorrowCap == currentBorrowCap) return currentBorrowCap;

        if (newBorrowCap > currentBorrowCap) {
            capConfig.lastIncreaseTime = _uint48(block.timestamp);
        }

        capConfig.lastUpdateBlock = _uint48(block.number);

        borrowCapConfigs[asset] = capConfig;

        IPoolConfiguratorLike(poolConfigurator).setBorrowCap(asset, newBorrowCap);

        emit UpdateBorrowCap(asset, currentBorrowCap, newBorrowCap);

        return newBorrowCap;
    }

}
