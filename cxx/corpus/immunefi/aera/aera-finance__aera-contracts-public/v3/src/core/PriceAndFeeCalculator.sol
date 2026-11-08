// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";
import { Math } from "@oz/utils/math/Math.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

import { BaseFeeCalculator } from "src/core/BaseFeeCalculator.sol";
import { ONE_DAY, ONE_IN_BPS, ONE_MINUTE, UNIT_PRICE_PRECISION } from "src/core/Constants.sol";
import { HasNumeraire } from "src/core/HasNumeraire.sol";
import { VaultAccruals, VaultPriceState } from "src/core/Types.sol";
import { IPriceAndFeeCalculator } from "src/core/interfaces/IPriceAndFeeCalculator.sol";
import { IOracleRegistry } from "src/periphery/interfaces/IOracleRegistry.sol";

/// @title PriceAndFeeCalculator
/// @notice Calculates and manages unit price and fees for multiple vaults that share the same numeraire token. Acts as
/// a price oracle and fee accrual engine. Vault registration workflow is:
/// 1. Register a new vault with registerVault()
/// 2. Set the thresholds for the vault with setThresholds()
/// 3. Set the initial price state with setInitialPrice()
/// Once registered, a vault can have its price updated by an authorized entity. Vault owners set thresholds for price
/// changes, update intervals, and price age. If a price update violates thresholds (too large change, too soon, or too
/// old), the vault is paused. Paused vaults dont accrue fees and cannot have their price updated until they are
/// unpaused by the vault owner. Accrues fees on each price update, based on TVL and performance since last update
/// Supports conversion between vault units, tokens, and numeraire for deposits/withdrawals. All logic and state is
/// per-vault, supporting many vaults in parallel. Only vault owners can set thresholds pause/unpause their vaults,
/// whereas accountants can also pause their vaults
/// Integrates with an external oracle registry for token price conversions
contract PriceAndFeeCalculator is IPriceAndFeeCalculator, BaseFeeCalculator, HasNumeraire {
    using SafeCast for uint256;

    ////////////////////////////////////////////////////////////
    //                       Immutables                       //
    ////////////////////////////////////////////////////////////

    /// @notice Oracle registry contract for price feeds
    IOracleRegistry public immutable ORACLE_REGISTRY;

    ////////////////////////////////////////////////////////////
    //                        Storage                         //
    ////////////////////////////////////////////////////////////

    /// @notice Mapping of vault addresses to their state information
    mapping(address vault => VaultPriceState vaultPriceState) internal _vaultPriceStates;

    ////////////////////////////////////////////////////////////
    //                        Modifiers                        //
    ////////////////////////////////////////////////////////////

    modifier requiresVaultAuthOrAccountant(address vault) {
        // Requirements: check that the caller is either the vault's accountant or the vault's owner or has the
        // permission to call the function
        require(
            msg.sender == vaultAccountant[vault] || msg.sender == Auth(vault).owner()
                || Auth(vault).authority().canCall(msg.sender, address(this), msg.sig),
            Aera__CallerIsNotAuthorized()
        );
        _;
    }

    constructor(IERC20 numeraire, IOracleRegistry oracleRegistry, address owner_, Authority authority_)
        BaseFeeCalculator(owner_, authority_)
        HasNumeraire(address(numeraire))
    {
        // Requirements: check that the numeraire token and oracle registry are not zero address
        require(address(oracleRegistry) != address(0), Aera__ZeroAddressOracleRegistry());

        // Effects: set the numeraire token and oracle registry
        ORACLE_REGISTRY = oracleRegistry;
    }

    ////////////////////////////////////////////////////////////
    //              Public / External Functions               //
    ////////////////////////////////////////////////////////////

    /// @notice Register a new vault with the fee calculator
    function registerVault() external override {
        VaultPriceState storage vaultPriceState = _vaultPriceStates[msg.sender];
        // Requirements: check that the vault is not already registered
        require(vaultPriceState.timestamp == 0, Aera__VaultAlreadyRegistered());

        // Effects: initialize the vault state
        // timestamp is set to indicate vault registration
        vaultPriceState.timestamp = uint32(block.timestamp);

        // Log that vault was registered
        emit VaultRegistered(msg.sender);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function setInitialPrice(address vault, uint128 price, uint32 timestamp) external requiresVaultAuth(vault) {
        require(price != 0, Aera__InvalidPrice());

        VaultPriceState storage vaultPriceState = _vaultPriceStates[vault];

        // Requirements: check that the tresholds are set (which implies the vault is registered) and the initial price
        // is not set
        require(vaultPriceState.maxPriceAge != 0, Aera__ThresholdNotSet());
        require(vaultPriceState.unitPrice == 0, Aera__VaultAlreadyInitialized());

        // Requirements: check that the provided timestamp is not too old and implicitly
        // check that timestamp <= block.timestamp
        require(block.timestamp - timestamp <= vaultPriceState.maxPriceAge, Aera__StalePrice());

        uint32 timestampU32 = uint32(block.timestamp);

        // Effects: set the initial price state
        vaultPriceState.unitPrice = price;
        vaultPriceState.highestPrice = price;
        vaultPriceState.timestamp = timestampU32;
        vaultPriceState.accrualLag = 0;
        vaultPriceState.lastTotalSupply = IERC20(vault).totalSupply().toUint128();

        // Log initial price state
        emit UnitPriceUpdated(vault, price, timestampU32);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function setThresholds(
        address vault,
        uint16 minPriceToleranceRatio,
        uint16 maxPriceToleranceRatio,
        uint16 minUpdateIntervalMinutes,
        uint8 maxPriceAge,
        uint8 maxUpdateDelayDays
    ) external requiresVaultAuth(vault) {
        // Requirements: check that the min price decrease ratio is <= 100%
        require(minPriceToleranceRatio <= ONE_IN_BPS, Aera__InvalidMinPriceToleranceRatio());
        // Requirements: check that the max price increase ratio is >= 100%
        require(maxPriceToleranceRatio >= ONE_IN_BPS, Aera__InvalidMaxPriceToleranceRatio());
        // Requirements: check that the max price age is greater than zero
        require(maxPriceAge > 0, Aera__InvalidMaxPriceAge());
        // Requirements: check that the max update delay is greater than zero
        require(maxUpdateDelayDays > 0, Aera__InvalidMaxUpdateDelayDays());

        VaultPriceState storage vaultPriceState = _vaultPriceStates[vault];

        // Requirements: check that the vault is registered
        require(vaultPriceState.timestamp != 0, Aera__VaultNotRegistered());

        // Effects: set the thresholds
        vaultPriceState.minPriceToleranceRatio = minPriceToleranceRatio;
        vaultPriceState.maxPriceToleranceRatio = maxPriceToleranceRatio;
        vaultPriceState.minUpdateIntervalMinutes = minUpdateIntervalMinutes;
        vaultPriceState.maxPriceAge = maxPriceAge;
        vaultPriceState.maxUpdateDelayDays = maxUpdateDelayDays;

        // Log that the thresholds were set
        emit ThresholdsSet(vault, minPriceToleranceRatio, maxPriceToleranceRatio, minUpdateIntervalMinutes, maxPriceAge);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function setUnitPrice(address vault, uint128 price, uint32 timestamp) external onlyVaultAccountant(vault) {
        VaultPriceState storage vaultPriceState = _vaultPriceStates[vault];

        // Requirements: validate the price update
        _validatePriceUpdate(vaultPriceState, price, timestamp);

        if (!vaultPriceState.paused) {
            if (_shouldPause(vaultPriceState, price, timestamp)) {
                // Effects + Log: pause the vault
                _setVaultPaused(vaultPriceState, vault, true);
                // Effects: write the accrual lag
                unchecked {
                    // Cant overflow because _validatePriceUpdate requires timestamp > vaultPriceState.timestamp
                    vaultPriceState.accrualLag = uint24(timestamp - vaultPriceState.timestamp);
                }
            } else {
                // Effects: accrue fees
                _accrueFees(vault, price, timestamp);
            }
        } else {
            // Effects: set the accrual lag
            unchecked {
                // Cant overflow because _validatePriceUpdate requires timestamp > vaultPriceState.timestamp
                vaultPriceState.accrualLag = uint24(timestamp - vaultPriceState.timestamp + vaultPriceState.accrualLag);
            }
        }

        // Effects: set the unit price and last update timestamp
        vaultPriceState.unitPrice = price;
        vaultPriceState.timestamp = timestamp;

        // Log the unit price update
        emit UnitPriceUpdated(vault, price, timestamp);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function pauseVault(address vault) external requiresVaultAuthOrAccountant(vault) {
        VaultPriceState storage vaultPriceState = _vaultPriceStates[vault];

        // Requirements: check that the vault is not already paused
        require(!vaultPriceState.paused, Aera__VaultPaused());

        // Effects + Log: pause the vault
        _setVaultPaused(vaultPriceState, vault, true);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function unpauseVault(address vault, uint128 price, uint32 timestamp) external requiresVaultAuth(vault) {
        VaultPriceState storage vaultPriceState = _vaultPriceStates[vault];

        // Requirements: check that the vault is paused, and unitPrice and timestamp match what is expected
        require(vaultPriceState.paused, Aera__VaultNotPaused());
        require(vaultPriceState.unitPrice == price, Aera__UnitPriceMismatch());
        require(vaultPriceState.timestamp == timestamp, Aera__TimestampMismatch());

        // Effects: accrue fees
        _accrueFees(vault, price, timestamp);

        // Effects + Log: unpause the vault
        _setVaultPaused(vaultPriceState, vault, false);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function resetHighestPrice(address vault) external requiresVaultAuth(vault) {
        VaultPriceState storage vaultPriceState = _vaultPriceStates[vault];
        uint128 currentPrice = vaultPriceState.unitPrice;

        // Requirements: check that the vault is initialized
        require(currentPrice != 0, Aera__VaultNotInitialized());

        // Requirements: check that we're resetting from a higher mark to a lower one
        require(currentPrice < vaultPriceState.highestPrice, Aera__CurrentPriceAboveHighestPrice());

        // Effects: reset the highest price to the current unit price
        vaultPriceState.highestPrice = currentPrice;

        // Log the highest price reset
        emit HighestPriceReset(vault, currentPrice);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function convertUnitsToToken(address vault, IERC20 token, uint256 unitsAmount)
        external
        view
        returns (uint256 tokenAmount)
    {
        return _convertUnitsToToken(vault, token, unitsAmount, _vaultPriceStates[vault].unitPrice, Math.Rounding.Floor);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function convertUnitsToTokenIfActive(address vault, IERC20 token, uint256 unitsAmount, Math.Rounding rounding)
        external
        view
        returns (uint256 tokenAmount)
    {
        VaultPriceState storage vaultState = _vaultPriceStates[vault];

        // check that the vault is not paused
        require(!vaultState.paused, Aera__VaultPaused());

        return _convertUnitsToToken(vault, token, unitsAmount, vaultState.unitPrice, rounding);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function convertUnitsToNumeraire(address vault, uint256 unitsAmount) external view returns (uint256) {
        VaultPriceState storage vaultState = _vaultPriceStates[vault];

        // check that the vault is not paused
        require(!vaultState.paused, Aera__VaultPaused());

        return unitsAmount * vaultState.unitPrice / UNIT_PRICE_PRECISION;
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function convertTokenToUnits(address vault, IERC20 token, uint256 tokenAmount)
        external
        view
        returns (uint256 unitsAmount)
    {
        return _convertTokenToUnits(vault, token, tokenAmount, _vaultPriceStates[vault].unitPrice, Math.Rounding.Floor);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function convertTokenToUnitsIfActive(address vault, IERC20 token, uint256 tokenAmount, Math.Rounding rounding)
        external
        view
        returns (uint256 unitsAmount)
    {
        VaultPriceState storage vaultState = _vaultPriceStates[vault];

        // check that the vault is not paused
        require(!vaultState.paused, Aera__VaultPaused());

        return _convertTokenToUnits(vault, token, tokenAmount, vaultState.unitPrice, rounding);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function getVaultState(address vault) external view returns (VaultPriceState memory, VaultAccruals memory) {
        return (_vaultPriceStates[vault], _vaultAccruals[vault]);
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function getVaultsPriceAge(address vault) external view returns (uint256) {
        unchecked {
            // Cant overflow because timestamp is required to be <= block.timestamp at the time of the update
            return block.timestamp - _vaultPriceStates[vault].timestamp;
        }
    }

    /// @inheritdoc IPriceAndFeeCalculator
    function isVaultPaused(address vault) external view returns (bool) {
        return _vaultPriceStates[vault].paused;
    }

    /// @inheritdoc BaseFeeCalculator
    function previewFees(address vault, uint256 feeTokenBalance) external view override returns (uint256, uint256) {
        VaultAccruals storage vaultAccruals = _vaultAccruals[vault];

        uint256 claimableProtocolFee = Math.min(feeTokenBalance, vaultAccruals.accruedProtocolFees);
        uint256 claimableVaultFee;
        unchecked {
            claimableVaultFee = Math.min(feeTokenBalance - claimableProtocolFee, vaultAccruals.accruedFees);
        }

        return (claimableVaultFee, claimableProtocolFee);
    }

    ////////////////////////////////////////////////////////////
    //              Internal / Private Functions              //
    ////////////////////////////////////////////////////////////

    /// @notice Accrues fees for a vault
    /// @param vault The address of the vault
    /// @param price The price of a single vault unit
    /// @param timestamp The timestamp of the price update
    /// @dev It is assumed that validation has already been done
    /// Tvl is calculated as the product of the minimum of the current and last price and the minimum of the current and
    /// last total supply. This is to minimize potential issues with price spikes
    function _accrueFees(address vault, uint256 price, uint256 timestamp) internal {
        VaultPriceState storage vaultPriceState = _vaultPriceStates[vault];

        uint256 timeDelta;
        unchecked {
            timeDelta = timestamp - vaultPriceState.timestamp + vaultPriceState.accrualLag;
        }

        // Interactions: get the current total supply
        uint256 currentTotalSupply = IERC20(vault).totalSupply();
        uint256 minTotalSupply = Math.min(currentTotalSupply, uint256(vaultPriceState.lastTotalSupply));
        uint256 minUnitPrice = Math.min(price, uint256(vaultPriceState.unitPrice));

        uint256 tvl = minUnitPrice * minTotalSupply / UNIT_PRICE_PRECISION;

        VaultAccruals storage vaultAccruals = _vaultAccruals[vault];
        uint256 vaultFeesEarned = _calculateTvlFee(tvl, vaultAccruals.fees.tvl, timeDelta);

        uint256 protocolFeesEarned = _calculateTvlFee(tvl, protocolFees.tvl, timeDelta);

        if (price > vaultPriceState.highestPrice) {
            uint256 profit = (price - vaultPriceState.highestPrice) * minTotalSupply / UNIT_PRICE_PRECISION;
            vaultFeesEarned += _calculatePerformanceFee(profit, vaultAccruals.fees.performance);
            protocolFeesEarned += _calculatePerformanceFee(profit, protocolFees.performance);

            // Effects: update the highest price
            vaultPriceState.highestPrice = uint128(price);
        }

        // Effects: update the accrued fees
        vaultAccruals.accruedFees += vaultFeesEarned.toUint112();
        vaultAccruals.accruedProtocolFees += protocolFeesEarned.toUint112();

        // Effects: update the last total supply and last fee accrual
        vaultPriceState.lastTotalSupply = currentTotalSupply.toUint128();
        vaultPriceState.accrualLag = 0;
    }

    /// @notice Sets the paused state for a vault
    /// @param vaultPriceState The storage pointer to the vault's price state
    /// @param vault The address of the vault
    /// @param paused The new paused state
    function _setVaultPaused(VaultPriceState storage vaultPriceState, address vault, bool paused) internal {
        // Effects: set the vault paused state
        vaultPriceState.paused = paused;

        // Log the vault paused state change
        emit VaultPausedChanged(vault, paused);
    }

    /// @notice Converts a token amount to units
    /// @param vault The address of the vault
    /// @param token The token to convert
    /// @param tokenAmount The amount of tokens to convert
    /// @param unitPrice The price of a single vault unit
    /// @param rounding The rounding direction
    /// @return unitsAmount The amount of units
    function _convertTokenToUnits(
        address vault,
        IERC20 token,
        uint256 tokenAmount,
        uint256 unitPrice,
        Math.Rounding rounding
    ) internal view returns (uint256 unitsAmount) {
        if (address(token) != NUMERAIRE) {
            tokenAmount = ORACLE_REGISTRY.getQuoteForUser(tokenAmount, address(token), NUMERAIRE, vault);
        }

        return Math.mulDiv(tokenAmount, UNIT_PRICE_PRECISION, unitPrice, rounding);
    }

    /// @notice Converts a units amount to tokens
    /// @param vault The address of the vault
    /// @param token The token to convert
    /// @param unitsAmount The amount of units to convert
    /// @param unitPrice The price of a single vault unit
    /// @param rounding The rounding direction
    /// @return tokenAmount The amount of tokens
    function _convertUnitsToToken(
        address vault,
        IERC20 token,
        uint256 unitsAmount,
        uint256 unitPrice,
        Math.Rounding rounding
    ) internal view returns (uint256 tokenAmount) {
        uint256 numeraireAmount = Math.mulDiv(unitsAmount, unitPrice, UNIT_PRICE_PRECISION, rounding);

        if (address(token) == NUMERAIRE) {
            return numeraireAmount;
        }

        return ORACLE_REGISTRY.getQuoteForUser(numeraireAmount, NUMERAIRE, address(token), vault);
    }

    /// @notice Validates a price update
    /// @dev Price is invalid if it is 0, before the last update, in the future, or if the price age is stale
    /// @param vaultPriceState The storage pointer to the vault's price state
    /// @param price The price of a single vault unit
    /// @param timestamp The timestamp of the price update
    function _validatePriceUpdate(VaultPriceState storage vaultPriceState, uint256 price, uint256 timestamp)
        internal
        view
    {
        // check that the price is not 0
        require(price != 0, Aera__InvalidPrice());
        // check that the price is not before the last update
        require(timestamp > vaultPriceState.timestamp, Aera__TimestampMustBeAfterLastUpdate());
        // check that the price is not in the future
        require(block.timestamp >= timestamp, Aera__TimestampCantBeInFuture());

        uint256 maxPriceAge = vaultPriceState.maxPriceAge;
        // check that the thresholds are set
        require(maxPriceAge != 0, Aera__ThresholdNotSet());
        // check update price age
        require(maxPriceAge + timestamp >= block.timestamp, Aera__StalePrice());
    }

    /// @notice Determines if a price update should pause the vault
    /// @dev Vault should pause if the price increase or decrease is too large, or if the min update interval has not
    /// passed
    /// @param state The storage pointer to the vault's price state
    /// @param price The price of a single vault unit
    /// @param timestamp The timestamp of the price update
    /// @return shouldPause True if the price update should pause the vault, false otherwise
    function _shouldPause(VaultPriceState storage state, uint256 price, uint32 timestamp)
        internal
        view
        returns (bool)
    {
        unchecked {
            uint256 lastUpdateTime = state.timestamp;
            // Cant overflow because minUpdateIntervalMinutes is uint16 and timestamp is uint32
            if (timestamp < state.minUpdateIntervalMinutes * ONE_MINUTE + lastUpdateTime) {
                return true;
            }

            // Cant overflow because timestamp is required to be > lastUpdateTime in _validatePriceUpdate
            if (timestamp - lastUpdateTime > state.maxUpdateDelayDays * ONE_DAY) {
                return true;
            }

            uint256 currentPrice = state.unitPrice;

            if (price > currentPrice) {
                // Cant overflow because maxPriceToleranceRatio is uint16 and currentPrice is uint128
                return price * ONE_IN_BPS > currentPrice * state.maxPriceToleranceRatio;
            } else {
                // Cant overflow because minPriceToleranceRatio is uint16 and currentPrice is uint128
                return price * ONE_IN_BPS < currentPrice * state.minPriceToleranceRatio;
            }
        }
    }
}