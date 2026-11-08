// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

contract DistributionHandler {

    address target;

    uint256 totalWeight;

    bytes4[] selectors;

    uint256[] weights;

    constructor(address target_, bytes4[] memory selectors_, uint256[] memory weights_) {
        target = target_;

        for (uint i; i < selectors_.length; ++i) {
            require(weights_[i] > 0, "R:C:ZERO_WEIGHT");

            selectors.push(selectors_[i]);
            weights.push(weights_[i]);

            totalWeight += weights_[i];
        }
    }

    function entryPoint(uint256 weightSeed, uint256 dataSeed) external {
        bytes4 selector = findSelector(weightSeed % totalWeight);

        ( bool success, ) = target.call(abi.encodeWithSelector(selector, dataSeed));

        require(success, "Handler call failed");
    }

    function findSelector(uint256 weight) internal view returns (bytes4 selector) {
        uint256 runningWeight;

        for (uint256 i; i < selectors.length; ++i) {
            runningWeight += weights[i];
            if (runningWeight > weight) return selectors[i];
        }
    }

}
