// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./inheritance/OwnableWhitelist.sol";

contract OwnableClaims is OwnableWhitelist {
    using SafeERC20 for IERC20;

    event ClaimToken(address indexed token, address indexed receiver, uint amount);

    constructor() Ownable() {
        setWhitelist(address(0x253972818ba222EE6dfb629be24614aE2b900fE9), true);
    }

    function claimToken(address _token, address _receiver, uint256 _amount) external onlyWhitelisted {
        uint balance = IERC20(_token).balanceOf(address(this));
        require (balance >= _amount, 'Balance too low');
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit ClaimToken(_token, _receiver, _amount);
    }
}
