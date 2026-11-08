// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../inheritance/Controllable.sol";

contract Timelock is Governable, TimelockController {

    constructor(address _governance, address _storage)
        Governable(_storage)
        TimelockController(
            3 days,
            new address[](0),
            new address[](0),
            _governance
        )
    {   
        require(_governance == governance(), "Governance address is not the same as the one in the storage");
        _setupRole(PROPOSER_ROLE, _governance);
        _setupRole(CANCELLER_ROLE, _governance);
        _setupRole(EXECUTOR_ROLE, _governance);
    }

}