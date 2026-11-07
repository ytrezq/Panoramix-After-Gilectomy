//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IPriceConvertor {
  function yCrvToUnderlying(uint256 _token_amount, uint256 i) external view returns (uint256);
}
