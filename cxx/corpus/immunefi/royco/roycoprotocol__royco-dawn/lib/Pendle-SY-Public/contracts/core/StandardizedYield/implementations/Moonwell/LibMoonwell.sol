// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import "./SolmateFixedPointLib.sol";
import "../../../../interfaces/Moonwell/IMToken.sol";

/// Copied & adapted interface from (https://github.com/moonwell-fi/moonwell-contracts-v2/blob/main/src/4626/LibCompound.sol)

/// @notice Get up to date mToken data without mutating state.
/// @author Transmissions11 (https://github.com/transmissions11/libcompound)
library LibMoonwell {
    using FixedPointMathLib for uint256;

    function viewUnderlyingBalanceOf(IMErc20 mToken, address user) internal view returns (uint256) {
        return mToken.balanceOf(user).mulWadDown(viewExchangeRate(mToken));
    }

    function viewExchangeRate(IMErc20 mToken) internal view returns (uint256) {
        uint256 accrualBlockTimestampPrior = mToken.accrualBlockTimestamp();

        if (accrualBlockTimestampPrior == block.timestamp) {
            return mToken.exchangeRateStored();
        }

        uint256 totalCash = IMErc20(mToken.underlying()).balanceOf(address(mToken));
        uint256 borrowsPrior = mToken.totalBorrows();
        uint256 reservesPrior = mToken.totalReserves();

        uint256 borrowRateMantissa = IMInterestRateModel(mToken.interestRateModel()).getBorrowRate(
            totalCash,
            borrowsPrior,
            reservesPrior
        );

        require(borrowRateMantissa <= 0.0005e16, "RATE_TOO_HIGH"); // Same as borrowRateMaxMantissa in CTokenInterfaces.sol

        uint256 interestAccumulated = (borrowRateMantissa * (block.timestamp - accrualBlockTimestampPrior)).mulWadDown(
            borrowsPrior
        );

        uint256 totalReserves = mToken.reserveFactorMantissa().mulWadDown(interestAccumulated) + reservesPrior;
        uint256 totalBorrows = interestAccumulated + borrowsPrior;
        uint256 totalSupply = mToken.totalSupply();

        return
            totalSupply == 0
                ? IMToken(address(mToken)).exchangeRateStored() /// get initial exchange rate if total supply is 0
                : (totalCash + totalBorrows - totalReserves).divWadDown(totalSupply);
    }
}
