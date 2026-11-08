// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Minimal ERC20 for testing (USDT-like: 6 decimals, mint + transfers)
contract MockUSDT {
    // ERC20 metadata
    string public name;
    string public symbol;
    uint8 public constant decimals = 6;

    // ERC20 storage
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /// @notice Mint arbitrary amount (open faucet for tests)
    function mint(address to, uint256 value) external returns (bool) {
        require(to != address(0), "ERC20: mint to zero");
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(to != address(0), "ERC20: transfer to zero");
        uint256 bal = balanceOf[msg.sender];
        require(bal >= value, "ERC20: balance");
        unchecked {
            balanceOf[msg.sender] = bal - value;
            balanceOf[to] += value;
        }
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(to != address(0), "ERC20: transfer to zero");
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "ERC20: allowance");
        uint256 bal = balanceOf[from];
        require(bal >= value, "ERC20: balance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        unchecked {
            balanceOf[from] = bal - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
        return true;
    }
}
