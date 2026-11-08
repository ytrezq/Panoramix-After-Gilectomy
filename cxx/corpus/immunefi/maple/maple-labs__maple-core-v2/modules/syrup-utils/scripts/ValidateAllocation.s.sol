// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { console2 as console, Script } from "../modules/forge-std/src/Script.sol";

import { ISyrupDrip } from "../contracts/interfaces/ISyrupDrip.sol";

// NOTE: JSON file used as the input must be alphabetically sorted (across all levels).
struct AllocationFile {
    Allocation[] allocations;
    uint256 deadline;
    uint256 maxId;
    bytes32 root;
    string name;
}

// NOTE: Must specify `uint` as `string` since they are technically strings in the JSON.
// NOTE: Including the Merkle proofs when parsing the entire JSON causes stack too deep errors.
//       The proofs are fetched manually for each allocation to avoid this issue.
struct Allocation {
    address owner;
    string amount;
    uint256 id;
    // bytes[] proof;
}

contract ValidateAllocation is Script {

    function run() external {
        address drip     = vm.envAddress("SYRUP_DRIP");
        address governor = vm.envAddress("GOVERNOR");

        string memory path = vm.envString("ALLOCATION_FILE");
        string memory json = vm.readFile(path);

        console.log("Read allocation data from:", path);

        AllocationFile memory file = abi.decode(vm.parseJson(json), (AllocationFile));

        console.log("Successfully parsed all token allocations.\n");

        console.log("Token allocation summary:");
        console.log("- Name:        %s", file.name);
        console.log("- Merkle Root: %s", vm.toString(file.root));
        console.log("- Deadline:    %s", file.deadline);
        console.log("- Maximum ID:  %s\n", file.maxId);

        vm.prank(governor);
        ISyrupDrip(drip).allocate(file.root, file.deadline, file.maxId);

        console.log("Submitted token allocations to SyrupDrip at: %s\n", drip);

        for (uint256 i = 0; i < file.allocations.length; i++) {
            console.log("Claiming allocation (ID: %s):", file.allocations[i].id);
            console.log("- Owner: ", file.allocations[i].owner);
            console.log("- Amount:", file.allocations[i].amount);
            console.log("- Proof: ");

            string    memory key   = string.concat(".allocations[", vm.toString(i), "].proof");
            bytes32[] memory proof = abi.decode(vm.parseJson(json, key), (bytes32[]));

            for (uint256 j = 0; j < proof.length; j++) {
                console.log("    -", vm.toString(proof[j]));
            }

            vm.prank(file.allocations[i].owner);
            ISyrupDrip(drip).claim(
                file.allocations[i].id,
                file.allocations[i].owner,
                vm.parseUint(file.allocations[i].amount),
                proof
            );
        }
    }

}
