// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPriceOracle } from "./IPriceOracle.sol";

/// @title PeggedPriceOracle
/// @notice The PeggedPriceOracle is a temporary solution that will be used only
/// upon deployment while we wait for some partners to integrate and perform their
/// automated actions with (also) the HoneyFactory, without having to care about
/// the basket mode being triggered by either a stale oracle or a temporary depeg.
contract PeggedPriceOracle is IPriceOracle {
    function _priceData() internal view returns (IPriceOracle.Data memory) {
        return IPriceOracle.Data({ price: 1e18, publishTime: block.timestamp });
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   IPriceOracle FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceOracle
    function getPrice(address asset) external view returns (Data memory data) {
        asset;
        return _priceData();
    }

    /// @inheritdoc IPriceOracle
    function getPriceUnsafe(address asset) external view returns (Data memory data) {
        asset;
        return _priceData();
    }

    /// @inheritdoc IPriceOracle
    function getPriceNoOlderThan(address asset, uint256 age) external view returns (Data memory data) {
        asset;
        age;
        return _priceData();
    }

    /// @inheritdoc IPriceOracle
    function priceAvailable(address asset) external pure returns (bool) {
        asset;
        return true;
    }
}
