// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import "./Protocol.t.sol";

// /// @dev Test the transfer of ownership for core contracts
// contract TransferOwnershipTest is ProtocolTest {
//     function setUp() public virtual override {
//         super.setUp();
//         vm.rollFork(186_420);
//     }

//     /// @dev Test the transfer of ownership for all contracts
//     function test_TransferOwnership() public {
//         address owner = bgt.owner();
//         assertNotEq(owner, address(timelock));
//         vm.startPrank(owner);
//         bgt.transferOwnership(address(timelock));
//         assertEq(bgt.owner(), address(timelock));
//         beraChef.transferOwnership(address(timelock));
//         assertEq(beraChef.owner(), address(timelock));
//         blockRewardController.transferOwnership(address(timelock));
//         assertEq(blockRewardController.owner(), address(timelock));
//         distributor.transferOwnership(address(timelock));
//         assertEq(distributor.owner(), address(timelock));
//         factory.transferOwnership(address(timelock));
//         assertEq(factory.owner(), address(timelock));
//         bgtStaker.transferOwnership(address(timelock));
//         assertEq(bgtStaker.owner(), address(timelock));
//         feeCollector.transferOwnership(address(timelock));
//         assertEq(feeCollector.owner(), address(timelock));
//         honey.transferOwnership(address(timelock));
//         assertEq(honey.owner(), address(timelock));
//         honeyFactory.transferOwnership(address(timelock));
//         assertEq(honeyFactory.owner(), address(timelock));
//         vm.stopPrank();
//     }

//     function governanceActions() internal override {
//         test_TransferOwnership();
//     }
// }
