// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { DSTest }   from "../../modules/forge-std/lib/ds-test/src/test.sol";
import { stdMath }  from "../../modules/forge-std/src/StdMath.sol";
import { StdUtils } from "../../modules/forge-std/src//StdUtils.sol";

contract Utils is DSTest, StdUtils {

    function boundWithEqualChanceOfZero(uint256 input, uint256 minimum, uint256 maximum) internal view returns (uint256 output) {
        uint256 diff = maximum - minimum;

        // If not enough space to set minimum as midpoint, set maximum as midpoint.
        output = diff > minimum
            ? filterBelow(bound(input, minimum, maximum + diff), maximum)
            : filterAbove(bound(input, minimum - diff, maximum), minimum);
    }

    function filterAbove(uint256 input, uint256 threshold_) internal pure returns (uint256 output) {
        output = input > threshold_ ? input : 0;
    }

    function filterBelow(uint256 input, uint256 threshold_) internal pure returns (uint256 output) {
        output = input < threshold_ ? input : 0;
    }

    function maxIgnoreZero(uint256 a, uint256 b) internal pure returns (uint256 maximum) {
        maximum = a == 0 ? b : (b == 0 ? a : (a > b ? a : b));
    }

    function minIgnoreZero(uint256 a, uint256 b) internal pure returns (uint256 minimum) {
        minimum = a == 0 ? b : (b == 0 ? a : (a < b ? a : b));
    }

    function minIgnoreZero(uint256 a, uint256 b, uint256 c) internal pure returns (uint256 minimum) {
        minimum = minIgnoreZero(a, minIgnoreZero(b, c));
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256 maximum) {
        maximum = a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256 minimum) {
        minimum = a < b ? a : b;
    }

}
