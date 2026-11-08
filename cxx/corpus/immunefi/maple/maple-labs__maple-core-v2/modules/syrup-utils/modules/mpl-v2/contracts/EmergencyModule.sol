// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IERC20Like, IGlobalsLike } from "./interfaces/Interfaces.sol";
import { IEmergencyModule }         from "./interfaces/IEmergencyModule.sol";

contract EmergencyModule is IEmergencyModule {

    address public immutable globals;
    address public immutable token;

    constructor(address globals_, address token_) {
        globals = globals_;
        token   = token_;
    }

    modifier onlyGovernor {
        require(msg.sender == IGlobalsLike(globals).governor(), "EM:NOT_GOVERNOR");

        _;
    }

    function burn(address from_, uint256 amount_) external onlyGovernor {
        IERC20Like(token).burn(from_, amount_);
    }

    function mint(uint256 amount_) external onlyGovernor {
        IERC20Like(token).mint(IGlobalsLike(globals).mapleTreasury(), amount_);
    }

}
