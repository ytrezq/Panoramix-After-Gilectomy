// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {IConcreteStandardVaultImpl} from "../interface/IConcreteStandardVaultImpl.sol";

library ConcreteV2ConversionLib {
    using Math for uint256;

    function calcConvertToShares(
        uint256 assets,
        uint256 _totalSupply,
        uint256 _totalAssets,
        Math.Rounding rounding,
        bool safeMode
    ) internal pure returns (uint256 shares) {
        // setting uint256 decimalsOffset = 0;
        shares = assets.mulDiv(
            _totalSupply + 1, // + 10 ** decimalsOffset = 1
            _totalAssets + 1,
            rounding
        );
        if (safeMode && shares == 0) revert IConcreteStandardVaultImpl.InsufficientShares();
    }

    function calcConvertToAssets(
        uint256 shares,
        uint256 _totalSupply,
        uint256 _totalAssets,
        Math.Rounding rounding,
        bool safeMode
    ) internal pure returns (uint256 assets) {
        // setting uint256 decimalsOffset = 0;
        assets = shares.mulDiv(
            _totalAssets + 1, // + 10 ** decimalsOffset = 1
            _totalSupply + 1,
            rounding
        );
        if (safeMode && assets == 0) revert IConcreteStandardVaultImpl.InsufficientAssets();
    }
}
