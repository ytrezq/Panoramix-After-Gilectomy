// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CommonBase } from "forge-std/Base.sol";

import { Distributor as MerklDistributor, MerkleTree as MerkleTreeStruct } from "@merkl/Distributor.sol";

import { MerkleTree } from "./MerkleTree.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";

contract MerkleTreeHelper is CommonBase {
    MerklDistributor public merklDistributor;
    address internal swapper;
    address internal swapperRouter;
    address internal governor;

    bytes32[] public leaves;
    uint256 public currentIndex;

    MerkleTree public merkleTree;

    constructor(address _merklDistributor, address _governor, address _swapper, address _swapperRouter) {
        merklDistributor = MerklDistributor(_merklDistributor);
        swapper = _swapper;
        swapperRouter = _swapperRouter;
        governor = _governor;

        merkleTree = new MerkleTree();
    }

    // Builds a merkle tree for a single user with multiple tokens/amounts.
    function buildMerkleTree(
        address _user,
        address[] memory _tokens,
        uint256[] memory _amounts
    )
        public
        returns (bytes32[][] memory proofs, bytes32 root)
    {
        address[] memory users = new address[](1);
        users[0] = _user;

        address[][] memory tokens = new address[][](1);
        tokens[0] = _tokens;

        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = _amounts;

        (bytes32[][][] memory allProofs, bytes32 rootHash) = buildMerkleTree(users, tokens, amounts);

        return (allProofs[0], rootHash);
    }

    // Builds merkle tree for multiple users at once.
    function buildMerkleTree(
        address[] memory users,
        address[][] memory tokens,
        uint256[][] memory amounts
    )
        public
        returns (bytes32[][][] memory allProofs, bytes32 root)
    {
        delete leaves;

        // Build leaves for all users
        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = 0; j < tokens[i].length; j++) {
                address token = tokens[i][j];
                uint256 amount = amounts[i][j];
                address user = users[i];

                leaves.push(keccak256(abi.encode(user, token, amount)));

                if (user.code.length == 0) {
                    vm.prank(user);
                    merklDistributor.setClaimRecipient(swapper, token);
                }

                vm.prank(swapper);
                MockERC20(token).approve(swapperRouter, type(uint192).max);

                MockERC20(token).mint(address(merklDistributor), amount);
            }
        }

        // Update merkle root once with all leaves
        root = merkleTree.getRoot(leaves);

        vm.prank(governor);
        merklDistributor.updateTree(MerkleTreeStruct({ merkleRoot: root, ipfsHash: bytes32(0) }));

        vm.warp(merklDistributor.endOfDisputePeriod() + 1);

        // Generate proofs for all users
        allProofs = new bytes32[][][](users.length);
        uint256 leafIndex = 0;
        for (uint256 i = 0; i < users.length; i++) {
            allProofs[i] = new bytes32[][](tokens[i].length);
            for (uint256 j = 0; j < tokens[i].length; j++) {
                allProofs[i][j] = merkleTree.getProof(leaves, leafIndex);
                leafIndex++;
            }
        }
    }
}
