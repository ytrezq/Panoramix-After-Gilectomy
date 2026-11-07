// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@layerzerolabs/solidity-examples/contracts/token/oft/OFT.sol";

contract GS is Ownable, OFT {
    uint256 public s_maxSupply = 16000000 * (10**18);

    constructor(address lzEndpoint) OFT("GammaSwap", "GS", lzEndpoint) {
        _mint(msg.sender, s_maxSupply);
    }

    function _mint(address to, uint256 amount) internal override(ERC20) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20) {
        super._burn(account, amount);
    }
}