// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {

    address public owner;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        owner = msg.sender;
        _mint(msg.sender, 100000 * 1e18);
    }

    function getSender() public virtual view returns(address) {
        return msg.sender;
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
