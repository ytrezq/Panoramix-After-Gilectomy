// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IUniV3VaultFactory {
  function deploy(address _storage, uint256 univ3PoolId) external returns (address vault);
  function info(address vault) external view returns(address[] memory Underlying, address NewVault, address DataContract, uint256 FeeAmount, uint256 PosId);
}
