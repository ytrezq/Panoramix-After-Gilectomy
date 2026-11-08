// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";

import {IMonopolizedOnDemandLP} from "../interfaces/IMonopolizedOnDemandLP.sol";
import {IOnDemandRWAUnderlying} from "../interfaces/IOnDemandRWAUnderlying.sol";
import {
    AddressValidation,
    TYPE_MONOPOLIZED_ON_DEMAND_LP,
    TYPE_ON_DEMAND_RWA_UNDERLYING
} from "../libraries/AddressValidation.sol";

/// @title  Monopolized On-demand LP
/// @author Gearbox Foundation
/// @notice A contract that allows a single depositor to provide liquidity to pools on demand by giving
///         approval of the corresponding token to this contract.
contract MonopolizedOnDemandLP is IMonopolizedOnDemandLP {
    using SafeERC20 for ERC20;
    using AddressValidation for IAddressProvider;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant contractType = TYPE_MONOPOLIZED_ON_DEMAND_LP;
    uint256 public constant version = 3_10;

    IAddressProvider internal immutable _ADDRESS_PROVIDER;
    IMarketConfigurator internal immutable _MARKET_CONFIGURATOR;
    address internal immutable _DEPOSITOR;
    EnumerableSet.AddressSet internal _poolsSet;
    EnumerableSet.AddressSet internal _underlyingsSet;

    constructor(IAddressProvider addressProvider, IMarketConfigurator marketConfigurator, address depositor) {
        if (!addressProvider.isMarketConfigurator(address(marketConfigurator))) {
            revert InvalidMarketConfiguratorException(address(marketConfigurator));
        }
        _ADDRESS_PROVIDER = addressProvider;
        _MARKET_CONFIGURATOR = marketConfigurator;
        _DEPOSITOR = depositor;
    }

    function serialize() external view override returns (bytes memory) {
        return abi.encode(_MARKET_CONFIGURATOR, _DEPOSITOR, getPools());
    }

    function getMarketConfigurator() external view override returns (address) {
        return address(_MARKET_CONFIGURATOR);
    }

    function getDepositor() external view override returns (address) {
        return _DEPOSITOR;
    }

    function getPools() public view override returns (Pool[] memory pools) {
        uint256 length = _poolsSet.length();
        pools = new Pool[](length);
        for (uint256 i; i < length; ++i) {
            address pool = _poolsSet.at(i);
            (address wrapped, address unwrapped) = _getUnderlyingTokens(pool);
            pools[i] = Pool({
                pool: pool,
                wrappedUnderlying: wrapped,
                unwrappedUnderlying: unwrapped,
                depositAllowance: depositAllowance(pool),
                claimableAmount: claimableAmount(pool)
            });
        }
    }

    function isPool(address pool) public view override returns (bool) {
        return _poolsSet.contains(pool);
    }

    function addPool(address pool) external override {
        if (msg.sender != _MARKET_CONFIGURATOR.admin()) revert CallerIsNotMarketConfiguratorAdminException(msg.sender);
        if (!AddressValidation.isRegisteredPool(address(_MARKET_CONFIGURATOR), pool)) {
            revert InvalidPoolException(pool);
        }
        address wrapped = _getAsset(pool);
        if (
            !_ADDRESS_PROVIDER.hasType(wrapped, TYPE_ON_DEMAND_RWA_UNDERLYING)
                || IOnDemandRWAUnderlying(wrapped).getLiquidityProvider() != address(this)
        ) revert InvalidUnderlyingTokenException(wrapped);
        address unwrapped = _getAsset(wrapped);

        if (!_poolsSet.add(pool)) revert PoolAlreadyAddedException(pool);
        if (!_underlyingsSet.add(unwrapped)) revert UnderlyingAlreadyAddedException(unwrapped);
        emit AddPool({pool: pool, wrappedUnderlying: wrapped, unwrappedUnderlying: unwrapped});

        ERC20(unwrapped).forceApprove(wrapped, type(uint256).max);
        ERC20(wrapped).forceApprove(pool, type(uint256).max);
    }

    function depositAllowance(address pool) public view override returns (uint256) {
        if (!isPool(pool)) return 0;
        (, address unwrapped) = _getUnderlyingTokens(pool);
        return Math.min(_getBalance(unwrapped, _DEPOSITOR), ERC20(unwrapped).allowance(_DEPOSITOR, address(this)));
    }

    /// @dev `creditAccount` parameter is ignored in this implementation
    function deposit(address pool, address, uint256 underlyingAmount) external override {
        _checkPool(pool);
        (address wrapped, address unwrapped) = _getUnderlyingTokens(pool);
        if (msg.sender != wrapped) revert CallerIsNotUnderlyingTokenException(msg.sender);
        ERC20(unwrapped).safeTransferFrom(_DEPOSITOR, address(this), underlyingAmount);
        _deposit(wrapped, underlyingAmount, address(this));
        _deposit(pool, underlyingAmount, address(this));
    }

    function claimableAmount(address pool) public view override returns (uint256) {
        if (!isPool(pool)) return 0;
        return ERC4626(pool).maxWithdraw(address(this));
    }

    function claim(address pool) external override {
        _checkPool(pool);
        if (msg.sender != _DEPOSITOR) revert CallerIsNotDepositorException(msg.sender);
        _withdraw(pool, ERC4626(pool).maxWithdraw(address(this)), address(this));
        address wrapped = _getAsset(pool);
        _withdraw(wrapped, _getBalance(wrapped, address(this)), _DEPOSITOR);
    }

    function _checkPool(address pool) internal view {
        if (!isPool(pool)) revert InvalidPoolException(pool);
    }

    function _getUnderlyingTokens(address pool) internal view returns (address wrapped, address unwrapped) {
        wrapped = _getAsset(pool);
        unwrapped = _getAsset(wrapped);
    }

    function _getBalance(address token, address account) internal view returns (uint256) {
        return ERC20(token).balanceOf(account);
    }

    function _getAsset(address vault) internal view returns (address) {
        return ERC4626(vault).asset();
    }

    function _deposit(address vault, uint256 assets, address receiver) internal {
        ERC4626(vault).deposit(assets, receiver);
    }

    function _withdraw(address vault, uint256 assets, address receiver) internal {
        ERC4626(vault).withdraw(assets, receiver, address(this));
    }
}
