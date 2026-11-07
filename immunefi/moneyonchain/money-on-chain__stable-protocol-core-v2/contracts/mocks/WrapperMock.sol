// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IWrapper } from "../interfaces/IWrapper.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WrapperMock is IWrapper, ERC20 {
    constructor() ERC20("WRAPPER", "WRAPPER") {}

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        (bool success, ) = msg.sender.call{ value: amount }("");
        // solhint-disable-next-line gas-custom-errors
        require(success, "transfer failed");
    }
}
