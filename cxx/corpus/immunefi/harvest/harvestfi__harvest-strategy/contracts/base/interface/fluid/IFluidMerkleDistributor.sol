// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IFluidMerkleDistributor {
  function claim(
    address _recipient,
    uint256 _amount,
    uint8 _positoinType,
    bytes32 _positionId,
    uint256 _cycle,
    bytes32[] calldata _merkleProof,
    bytes memory _metadata
  ) external;
}
