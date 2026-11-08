// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";

import {IOnDemandRWAUnderlying} from "../interfaces/IOnDemandRWAUnderlying.sol";
import {IOnDemandLiquidityProvider} from "../interfaces/base/IOnDemandLiquidityProvider.sol";
import {IRWAFactory} from "../interfaces/base/IRWAFactory.sol";
import {
    AddressValidation,
    DOMAIN_ON_DEMAND_LP,
    DOMAIN_POOL,
    DOMAIN_RWA_FACTORY,
    TYPE_ON_DEMAND_RWA_UNDERLYING
} from "../libraries/AddressValidation.sol";

/// @title  On-demand RWA Underlying
/// @author Gearbox Foundation
/// @notice An ERC4626-like token wrapper to use as underlying in markets with RWA compliance and on-demand liquidity
///         provision. On top of blocking liquidations of frozen credit accounts, it also lets compliant users pull
///         liquidity from an on-demand LP contract right before borrowing, increasing capital efficiency for lenders.
///         Besides the liquidity provider and credit accounts, only users whitelisted by the market configurator admin
///         can send underlying to the pool in order to prevent dissolution of lenders' profits.
contract OnDemandRWAUnderlying is IOnDemandRWAUnderlying, ERC4626 {
    using AddressValidation for IAddressProvider;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant override contractType = TYPE_ON_DEMAND_RWA_UNDERLYING;
    uint256 public constant override version = 3_10;

    IAddressProvider internal immutable _ADDRESS_PROVIDER;
    IRWAFactory internal immutable _FACTORY;
    IOnDemandLiquidityProvider internal immutable _LIQUIDITY_PROVIDER;
    IMarketConfigurator internal immutable _MARKET_CONFIGURATOR;
    address internal _pool;
    EnumerableSet.AddressSet internal _allowedDepositors;

    modifier onlyMarketConfiguratorAdmin() {
        _ensureCallerIsMarketConfiguratorAdmin();
        _;
    }

    constructor(
        IAddressProvider addressProvider,
        IRWAFactory factory,
        IOnDemandLiquidityProvider liquidityProvider,
        IMarketConfigurator marketConfigurator,
        ERC20 underlying,
        string memory namePrefix,
        string memory symbolPrefix
    )
        ERC20(string.concat(namePrefix, underlying.name()), string.concat(symbolPrefix, underlying.symbol()))
        ERC4626(underlying)
    {
        if (!addressProvider.hasDomain(address(factory), DOMAIN_RWA_FACTORY)) {
            revert InvalidRWAFactoryException(address(factory));
        }
        if (!addressProvider.hasDomain(address(liquidityProvider), DOMAIN_ON_DEMAND_LP)) {
            revert InvalidLiquidityProviderException(address(liquidityProvider));
        }
        if (!addressProvider.isMarketConfigurator(address(marketConfigurator))) {
            revert InvalidMarketConfiguratorException(address(marketConfigurator));
        }
        _ADDRESS_PROVIDER = addressProvider;
        _FACTORY = factory;
        _LIQUIDITY_PROVIDER = liquidityProvider;
        _MARKET_CONFIGURATOR = marketConfigurator;
    }

    function serialize() external view override returns (bytes memory) {
        return abi.encode(_FACTORY, asset(), _pool, _LIQUIDITY_PROVIDER, _MARKET_CONFIGURATOR, getAllowedDepositors());
    }

    function getFactory() external view override returns (address) {
        return address(_FACTORY);
    }

    function getLiquidityProvider() external view override returns (address) {
        return address(_LIQUIDITY_PROVIDER);
    }

    function getMarketConfigurator() external view override returns (address) {
        return address(_MARKET_CONFIGURATOR);
    }

    function getPool() public view override returns (address pool) {
        pool = _pool;
        if (pool == address(0)) revert PoolNotSetException();
    }

    function setPool(address pool) external override onlyMarketConfiguratorAdmin {
        if (_pool != address(0)) revert PoolAlreadySetException();
        if (
            !_ADDRESS_PROVIDER.hasDomain(pool, DOMAIN_POOL) || ERC4626(pool).asset() != address(this)
                || !AddressValidation.isRegisteredPool(address(_MARKET_CONFIGURATOR), pool)
        ) revert InvalidPoolException(pool);
        _pool = pool;
        emit SetPool(pool);
    }

    function getAllowedDepositors() public view override returns (address[] memory) {
        return _allowedDepositors.values();
    }

    function isAllowedDepositor(address account) public view override returns (bool) {
        return account == address(_LIQUIDITY_PROVIDER) || _FACTORY.isCreditAccount(account)
            || _allowedDepositors.contains(account);
    }

    function setDepositorStatus(address account, bool allowed) external override onlyMarketConfiguratorAdmin {
        if (allowed && _allowedDepositors.add(account) || !allowed && _allowedDepositors.remove(account)) {
            emit SetDepositorStatus(account, allowed);
        }
    }

    function beforeTokenBorrow(address creditAccount, uint256 underlyingAmount) external override {
        address pool = getPool();
        if (msg.sender != _FACTORY.getWallet(creditAccount)) {
            revert CallerIsNotWalletException(msg.sender, creditAccount);
        }
        if (pool != ICreditManagerV3(ICreditAccountV3(creditAccount).creditManager()).pool()) {
            revert InvalidCreditAccountException(creditAccount);
        }
        _LIQUIDITY_PROVIDER.deposit(pool, creditAccount, underlyingAmount);
    }

    /// @dev Even though pools are assumed to use IRMs independent of utilization, this adjustment
    ///      is necessary in order to prevent available liquidity from underflowing on borrowing.
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return super.balanceOf(account) + (account == _pool ? _depositAllowance() : 0);
    }

    /// @dev Just to be a little more consistent with the `balanceOf` adjustment
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return super.totalSupply() + _depositAllowance();
    }

    function _convertToAssets(uint256 shares, Math.Rounding) internal pure override returns (uint256) {
        return shares;
    }

    function _convertToShares(uint256 assets, Math.Rounding) internal pure override returns (uint256) {
        return assets;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        _revertIfFrozenCreditAccount(from);
        _revertIfFrozenCreditAccount(to);

        address pool = _pool;
        if (pool == address(0)) return;
        if (to == pool && !isAllowedDepositor(from)) revert AccountIsNotAllowedDepositorException(from);
        if (from == pool && !isAllowedDepositor(to)) revert AccountIsNotAllowedDepositorException(to);
    }

    function _revertIfFrozenCreditAccount(address account) internal view {
        if (_FACTORY.isCreditAccount(account) && _FACTORY.isFrozen(account)) {
            revert FrozenCreditAccountException(account);
        }
    }

    function _ensureCallerIsMarketConfiguratorAdmin() internal view {
        if (msg.sender != _MARKET_CONFIGURATOR.admin()) revert CallerIsNotMarketConfiguratorAdminException(msg.sender);
    }

    function _depositAllowance() internal view returns (uint256) {
        address pool = _pool;
        return pool != address(0) ? _LIQUIDITY_PROVIDER.depositAllowance(pool) : 0;
    }
}
