// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC1820Registry } from "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import { IERC777Recipient } from "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ReentrancyAttackerERC777Mock is IERC777Recipient {
    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    address private dest;
    bytes private data;

    constructor() {
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function tokensReceived(
        address /*operator*/,
        address /*from*/,
        address /*to*/,
        uint256 /*amount*/,
        bytes calldata /*userData*/,
        bytes calldata /*operatorData*/
    ) external override {
        forward(dest, data);
    }

    function approve(address tokenAddress, address spender, uint256 amount) public returns (bool) {
        return IERC20(tokenAddress).approve(spender, amount);
    }

    function forward(address dest_, bytes memory data_) public {
        dest = dest_;
        data = data_;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory err) = dest_.call(data_);
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let returndata_size := mload(err)
                revert(add(32, err), returndata_size)
            }
        }
    }
}
