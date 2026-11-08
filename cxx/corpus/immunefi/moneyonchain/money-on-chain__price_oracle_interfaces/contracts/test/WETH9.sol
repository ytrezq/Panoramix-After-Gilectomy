// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

/// @notice 1:1 ERC‑20 wrapper for the native coin (e.g. RBTC) compatible with Uniswap V3 periphery.
contract WETH9 {
  string public name = "Wrapped RBTC";
  string public symbol = "WRBTC";
  uint8 public decimals = 18;

  event Approval(address indexed src, address indexed guy, uint wad);
  event Transfer(address indexed src, address indexed dst, uint wad);
  event Deposit(address indexed dst, uint wad);
  event Withdrawal(address indexed src, uint wad);

  mapping(address => uint) public balanceOf;
  mapping(address => mapping(address => uint)) public allowance;

  receive() external payable {
    deposit();
  }

  /// @notice Deposit native coin and mint 1:1 ERC‑20 `WETH` tokens.
  function deposit() public payable {
    balanceOf[msg.sender] += msg.value;
    emit Deposit(msg.sender, msg.value);
  }

  /// @notice Burn `wad` WETH and withdraw same amount of native coin.
  function withdraw(uint wad) public {
    require(balanceOf[msg.sender] >= wad, "WETH9: insufficient balance");
    balanceOf[msg.sender] -= wad;
    // In 0.7.x `msg.sender.transfer()` is allowed only if sender is payable.
    //(payable(msg.sender)).transfer(wad);
    msg.sender.transfer(wad);
    emit Withdrawal(msg.sender, wad);
  }

  /// @notice Current WETH supply — equal to contract’s native coin balance.
  function totalSupply() public view returns (uint) {
    return address(this).balance;
  }

  function approve(address guy, uint wad) public returns (bool) {
    allowance[msg.sender][guy] = wad;
    emit Approval(msg.sender, guy, wad);
    return true;
  }

  function transfer(address dst, uint wad) public returns (bool) {
    return transferFrom(msg.sender, dst, wad);
  }

  function transferFrom(address src, address dst, uint wad) public returns (bool) {
    require(balanceOf[src] >= wad, "WETH9: insufficient balance");
    if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
      require(allowance[src][msg.sender] >= wad, "WETH9: insufficient allowance");
      allowance[src][msg.sender] -= wad;
    }
    balanceOf[src] -= wad;
    balanceOf[dst] += wad;
    emit Transfer(src, dst, wad);
    return true;
  }
}
