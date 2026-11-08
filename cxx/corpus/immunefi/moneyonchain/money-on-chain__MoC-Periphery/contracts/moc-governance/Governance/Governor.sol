// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import {Initializable} from "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ChangeContract} from "./ChangeContract.sol";
import {IGovernor} from "./IGovernor.sol";

/**
  @title Governor
  @notice Basic governor that handles its governed contracts changes
  through trusting an external address
  */
contract Governor is Initializable, ReentrancyGuard, Ownable, IGovernor {
    address private currentChangeContract;

    constructor() public initializer {
        // Avoid leaving the implementation contract uninitialized.
    }

    function initialize(address sender) public override initializer {
        Ownable.initialize(sender);
        ReentrancyGuard.initialize();
    }

    function executeChange(ChangeContract changeContract) external override nonReentrant onlyOwner {
        enableChangeContract(changeContract);
        changeContract.execute();
        disableChangeContract();
    }

    function isAuthorizedChanger(address _changer) external view override returns (bool) {
        return currentChangeContract == _changer;
    }

    function enableChangeContract(ChangeContract changeContract) internal {
        currentChangeContract = address(changeContract);
    }

    function disableChangeContract() internal {
        currentChangeContract = address(0x0);
    }

    uint256[50] private upgradeGap;
}
