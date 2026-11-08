// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

contract FallbackMock {
    event GasBurned(uint256);
    uint256 public iterations;

    function forward(address dest_, bytes calldata data_) external payable {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = dest_.call{ value: msg.value }(data_);
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        }
    }

    function setIterations(uint256 iterations_) external {
        iterations = iterations_;
    }

    receive() external payable {
        for (uint256 i = 0; i < iterations; i++) {
            emit GasBurned(i);
        }
    }
}
