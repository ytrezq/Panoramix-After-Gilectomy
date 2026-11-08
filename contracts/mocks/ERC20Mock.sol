// SPDX-License-Identifier: MIT
// slither-disable-next-line solc-version
pragma solidity 0.8.24;

import { ERC20, ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract ERC20Mock is ERC20Burnable {
    uint256 internal constant UINT256_MAX = ~uint256(0);
    uint8 public customDecimals = 18;

    // There are existing ERC20 token deployments that reverts and others that return false
    // This state is used to test both
    enum FailType {
        notFail,
        failWithFalse, // always returns false in a transfer
        failWithRevert // always reverts in a transfer
    }

    FailType internal failType;

    constructor() ERC20("ERC20Mock", "ERC20Mock") {
        _mint(msg.sender, UINT256_MAX / 10 ** 10);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failType == FailType.failWithFalse) {
            return false;
        }
        if (failType == FailType.failWithRevert) {
            // solhint-disable-next-line
            require(false);
        }
        return super.transfer(to, amount);
    }

    function forceTransferToFail(FailType failType_) external {
        failType = failType_;
    }

    function setDecimals(uint8 customDecimals_) external {
        customDecimals = customDecimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return customDecimals;
    }
}
