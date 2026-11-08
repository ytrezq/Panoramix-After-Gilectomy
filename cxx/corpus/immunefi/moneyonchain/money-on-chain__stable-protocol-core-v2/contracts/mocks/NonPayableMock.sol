// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

contract NonPayableMock {
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
}
