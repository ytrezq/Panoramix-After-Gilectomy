// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC777 } from "@openzeppelin/contracts/token/ERC777/ERC777.sol";

contract ERC777Mock is ERC777 {
    uint256 internal constant UINT256_MAX = ~uint256(0);

    constructor(address[] memory _defaultOperators) ERC777("ERC777Mock", "ERC777Mock", _defaultOperators) {
        _mint(msg.sender, UINT256_MAX / 10 ** 10, "", "");
    }

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount, "", "");
    }

    function burn(address _account, uint256 _amount) external {
        _burn(_account, _amount, "", "");
    }
}
