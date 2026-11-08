// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {BatchScript} from "forge-safe/src/BatchScript.sol";
import {AaveV3ATokenWrapper} from "../src/AaveV3ATokenWrapper.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title TransferWrapperOwnership
/// @notice Queues an ownership transfer of the wrapper through the owning Safe batch.
contract TransferWrapperOwnership is BatchScript {
    address SAFE = 0x8C54cb62900Ec252E7992C85a5b7078A8AF4Fd7F;

    function run() external isBatch(SAFE) {
        require(block.chainid == 1, "not mainnet");

        string memory deploymentJson = vm.readFile("mainnet.json");
        address proxy = vm.parseJsonAddress(deploymentJson, ".proxy");
        AaveV3ATokenWrapper wrapper = AaveV3ATokenWrapper(proxy);

        string memory timelockJson = vm.readFile("TimelockDeployment_1.json");
        address newOwner = vm.parseJsonAddress(timelockJson, ".timelock");
        require(newOwner != address(0), "missing new owner");
        require(vm.parseJsonAddress(timelockJson, ".safe") == SAFE, "Safe mismatch");

        address currentOwner = wrapper.owner();
        require(currentOwner == SAFE, "Safe not owner");

        console2.log("Wrapper:", proxy);
        console2.log("Current owner:", currentOwner);
        console2.log("New owner:", newOwner);

        bytes memory transferTxn = abi.encodeCall(OwnableUpgradeable.transferOwnership, (newOwner));
        addToBatch(proxy, transferTxn);
        console2.log("queued transferOwnership for wrapper", proxy);

        executeBatch(true);
    }
}
