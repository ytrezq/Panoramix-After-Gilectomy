// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./InvariantBaseTest.t.sol";

contract FullSystemInvariantsTest is InvariantBaseTest {
    uint256 public maxDebtDeltaSeen;
    uint256 public maxEarmarkDeltaSeen;

    function setUp() public virtual override {
        super.setUp();
    }

    /* INVARIANTS */

    // Total debt in the system is equal to sum of all user debts
    function invariantConsistentDebtAndEarmark() public {
        address[] memory users = targetSenders();

        uint256 sumDebt;
        uint256 sumEarmarked;
        uint256 active;

        for (uint256 i; i < users.length; ++i) {
            uint256 tokenId = AlchemistNFTHelper.getFirstTokenId(users[i], address(alchemistNFT));
            if (tokenId != 0) {
                active++;
                (, uint256 debt, uint256 earmarked) = alchemist.getCDP(tokenId);
                sumDebt += debt;
                sumEarmarked += earmarked;
            }
        }

        uint256 totalDebt = alchemist.totalDebt();
        uint256 cumEarmarked = alchemist.getUnrealizedCumulativeEarmarked();

        uint256 debtDelta = _absDiff(sumDebt, totalDebt);
        uint256 earmarkDelta = _absDiff(sumEarmarked, cumEarmarked);

        if (debtDelta > maxDebtDeltaSeen) maxDebtDeltaSeen = debtDelta;
        if (earmarkDelta > maxEarmarkDeltaSeen) maxEarmarkDeltaSeen = earmarkDelta;

        // Tolerance:
        // - base: 100
        // - plus: conversionFactor * active positions
        uint256 cf = alchemist.underlyingConversionFactor();
        uint256 tol = _max(100, cf * _max(active, 1));

        if (debtDelta > tol || earmarkDelta > tol) {
            emit log_named_uint("debtDelta", debtDelta);
            emit log_named_uint("earmarkDelta", earmarkDelta);
            emit log_named_uint("sumDebt", sumDebt);
            emit log_named_uint("totalDebt", totalDebt);
            emit log_named_uint("sumEarmarked", sumEarmarked);
            emit log_named_uint("cumEarmarked", cumEarmarked);
            emit log_named_uint("tol", tol);
        }

        assertLe(debtDelta, tol);
        assertLe(earmarkDelta, tol);

        // Sanity invariants that should ALWAYS hold
        assertLe(cumEarmarked, totalDebt);
        assertLe(sumEarmarked, sumDebt);
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
