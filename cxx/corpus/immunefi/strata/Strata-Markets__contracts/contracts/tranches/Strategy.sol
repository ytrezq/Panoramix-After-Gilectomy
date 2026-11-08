// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IStrategy } from "./interfaces/IStrategy.sol";
import { CDOComponent }  from "./base/CDOComponent.sol";

/// @title Strategy
/// @notice Abstract base contract for CDO investment strategies
/// @dev Provides a foundation for concrete strategy implementations
/// @dev Concrete strategies must implement specific investment logic by extending this contract
abstract contract Strategy is IStrategy, CDOComponent {

    /**
     * @notice Returns the deposit fee percentage for the underlying protocol
     * @return feeBps The deposit fee in basis points (e.g., 10 = 0.1%)
     */
    function depositFeeBps (address) external virtual view returns (uint256 feeBps) {
        return 0;
    }
}
