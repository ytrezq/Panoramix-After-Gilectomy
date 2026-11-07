// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ConcreteV2ConstantsLib {
    /// @dev Fee denominator for basis points calculation (10_000 = 100%)
    uint16 public constant BASIS_POINTS_DENOMINATOR = 10_000;
}

library ConcreteV2FeeParamsLib {
    /// @dev Maximum management fee in basis points (10% = 1,000 bps)
    uint16 public constant MAX_MANAGEMENT_FEE = 1_000;

    /// @dev Maximum performance fee in basis points (30% = 3,000 bps)
    uint16 public constant MAX_PERFORMANCE_FEE = 3_000;
}
