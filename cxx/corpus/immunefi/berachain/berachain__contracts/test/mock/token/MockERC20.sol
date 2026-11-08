// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockERC20 is ERC20Upgradeable {
    function initialize(string memory name, string memory symbol) external initializer {
        __ERC20_init(name, symbol);
    }

    // Anyone can mint.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Anyone can burn.
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
