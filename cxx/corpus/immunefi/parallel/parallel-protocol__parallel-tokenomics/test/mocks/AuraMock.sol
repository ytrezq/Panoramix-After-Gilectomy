// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IAuraBoosterLite, IAuraRewardPool } from "contracts/interfaces/IAura.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "./ERC20Mock.sol";

contract AuraBoosterLiteMock is IAuraBoosterLite {
    IERC20 public bpt;
    ERC20Mock public auraBpt;

    constructor(address _bpt, address _auraBpt) {
        bpt = IERC20(_bpt);
        auraBpt = ERC20Mock(_auraBpt);
    }

    function deposit(uint256, uint256 _amount, bool) external returns (bool) {
        bpt.transferFrom(msg.sender, address(this), _amount);
        return true;
    }

    function withdrawTo(uint256, uint256 _amount, address _to) external returns (bool) {
        bpt.transfer(_to, _amount);
        return true;
    }
}

contract AuraRewardPoolMock is IAuraRewardPool {
    IAuraBoosterLite public booster;

    constructor(address _booster) {
        booster = IAuraBoosterLite(_booster);
    }

    function getReward() external returns (bool) {
        return true;
    }

    function withdrawAndUnwrap(uint256 amount, bool) external returns (bool) {
        booster.withdrawTo(0, amount, msg.sender);
        return true;
    }
}
