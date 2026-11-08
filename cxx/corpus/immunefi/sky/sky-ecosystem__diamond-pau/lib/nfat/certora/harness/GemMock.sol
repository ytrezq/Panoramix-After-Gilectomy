// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.24;

contract GemMock {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "GemMock/insufficient-balance");
        unchecked { balanceOf[msg.sender] -= amount; }
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        require(balanceOf[from] >= amount, "GemMock/insufficient-balance");
        require(allowance[from][msg.sender] >= amount, "GemMock/insufficient-allowance");
        unchecked {
            balanceOf[from] -= amount;
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}
