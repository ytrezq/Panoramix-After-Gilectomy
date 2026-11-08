// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IGovernor } from "../interfaces/IGovernor.sol";
import { IChangeContract } from "../interfaces/IChangeContract.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title InterimGovernor
 * @notice Basic governor that handles its governed contracts changes
 *  when are done by this contract owner.
 *  It is used to set parameters during the deployment and then the transfer
 *  to the real governor must be done
 */
contract InterimGovernor is IGovernor, Ownable {
    /**
     * @notice Function to be called to make the changes in changeContract
     * @param changeContract_ Address of the contract that will execute the changes
     */
    function executeChange(IChangeContract changeContract_) external onlyOwner {
        changeContract_.execute();
    }

    /**
     * @notice Only the owner can call protected functions on the Governed contract
     * @param caller_ Address of the caller of the protected function
     */
    function isAuthorizedChanger(address caller_) external view override returns (bool) {
        return caller_ == owner();
    }
}
