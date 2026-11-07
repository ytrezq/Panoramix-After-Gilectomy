// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

contract ActorUtil is Test {
    /// @dev actor[0] is the vault manager
    /// @dev actor[1] is the strategy operator
    /// @dev actor[2] is the allocator
    /// @dev actor[3] is the factory owner
    /// @dev actor[4] is the fee recipient
    /// @dev actor[5] is the user1
    address[] public actors;

    function includeActor(address _actor) external {
        actors.push(_actor);
    }

    function initiateExactActorCall(uint256 _actorIndex, address _target, bytes memory _calldata)
        external
        returns (address, bool, bytes memory)
    {
        address currentActor = _getExactActor(_actorIndex);

        vm.prank(currentActor);
        (bool success, bytes memory returnData) = address(_target).call(_calldata);

        return (currentActor, success, returnData);
    }

    function initiateActorCall(uint256 _actorIndexSeed, address _target, bytes memory _calldata)
        external
        returns (address, bool, bytes memory)
    {
        address currentActor = _getActor(_actorIndexSeed);

        vm.prank(currentActor);
        (bool success, bytes memory returnData) = address(_target).call(_calldata);

        return (currentActor, success, returnData);
    }

    function fetchActor(uint256 _actorIndexSeed) external view returns (address, uint256) {
        uint256 randomActorIndex = bound(_actorIndexSeed, 5, actors.length - 1);
        address randomActor = actors[randomActorIndex];

        return (randomActor, randomActorIndex);
    }

    function getActors() external view returns (address[] memory) {
        address[] memory actorsList = new address[](actors.length);

        for (uint256 i; i < actors.length; i++) {
            actorsList[i] = actors[i];
        }

        return actorsList;
    }

    function _getActor(uint256 _actorIndexSeed) internal view returns (address) {
        return actors[bound(_actorIndexSeed, 5, actors.length - 1)];
    }

    function _getExactActor(uint256 _actorIndex) internal view returns (address) {
        return actors[_actorIndex];
    }
}
