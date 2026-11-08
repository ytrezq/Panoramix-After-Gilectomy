// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";

import {IRWAFactory} from "../interfaces/base/IRWAFactory.sol";
import {IRWAUnderlying} from "../interfaces/base/IRWAUnderlying.sol";
import {AddressValidation, DOMAIN_RWA_FACTORY, TYPE_DEFAULT_RWA_UNDERLYING} from "../libraries/AddressValidation.sol";

/// @title  Default RWA Underlying
/// @author Gearbox Foundation
/// @notice An ERC4626-like token wrapper to use as underlying in markets with RWA compliance.
///         Exists primarily to block liquidations of frozen credit accounts since both full and partial liquidations
///         involve minting shares and returning them to the pool.
///         Other interactions with frozen credit accounts are blocked directly in the RWA factory contract.
contract DefaultRWAUnderlying is IRWAUnderlying, ERC4626 {
    using AddressValidation for IAddressProvider;

    bytes32 public constant override contractType = TYPE_DEFAULT_RWA_UNDERLYING;
    uint256 public constant override version = 3_10;

    IRWAFactory internal immutable _FACTORY;

    constructor(
        IAddressProvider addressProvider,
        IRWAFactory factory,
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
        _FACTORY = factory;
    }

    function serialize() external view virtual override returns (bytes memory) {
        return abi.encode(_FACTORY, asset());
    }

    function getFactory() external view override returns (address) {
        return address(_FACTORY);
    }

    function beforeTokenBorrow(address, uint256) external pure override {}

    function _convertToAssets(uint256 shares, Math.Rounding) internal pure override returns (uint256) {
        return shares;
    }

    function _convertToShares(uint256 assets, Math.Rounding) internal pure override returns (uint256) {
        return assets;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        _revertIfFrozenCreditAccount(from);
        _revertIfFrozenCreditAccount(to);
    }

    function _revertIfFrozenCreditAccount(address account) internal view {
        if (_FACTORY.isCreditAccount(account) && _FACTORY.isFrozen(account)) {
            revert FrozenCreditAccountException(account);
        }
    }
}
