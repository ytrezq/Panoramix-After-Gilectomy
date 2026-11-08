// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

contract ReentrancyAttackerMock {
    address internal dest;
    bytes internal data;
    bool internal entered;
    bytes internal returnError;
    bool internal isPayableFunction;

    function forward(address dest_, bytes memory data_, bool isPayableFunction_) public payable returns (bytes memory) {
        isPayableFunction = isPayableFunction_;
        dest = dest_;
        data = data_;
        bytes memory returndata;
        if (isPayableFunction) {
            // solhint-disable-next-line avoid-low-level-calls
            (, returndata) = dest_.call{ value: msg.value }(data_);
        } else {
            // solhint-disable-next-line avoid-low-level-calls
            (, returndata) = dest_.call(data_);
        }
        if (entered) return (returndata);
        returndata = returnError;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let returndata_size := mload(returndata)
            revert(add(32, returndata), returndata_size)
        }
    }

    // solhint-disable-next-line no-complex-fallback
    fallback() external payable {
        entered = true;
        bytes memory returndata = forward(dest, data, isPayableFunction);
        returnError = returndata;
        entered = false;
    }
}
