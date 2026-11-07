// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockTokenPermit } from "./MockTokenPermit.sol";

/// @dev ERC-3156 lender: mints the principal to the borrower and pulls back principal plus fee through the
/// allowance the borrower granted, mirroring FlashParallelToken closely enough for the rebalancer.
contract MockFlashLoan {
  bytes32 internal constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

  /// @dev Basis points, as FlashParallelToken stores it
  uint16 public feeRateBps;

  function setFeeRateBps(uint16 newFeeRateBps) external {
    require(newFeeRateBps <= 1e4, "fee rate above 100%");
    feeRateBps = newFeeRateBps;
  }

  function maxFlashLoan(address) external pure returns (uint256) {
    return type(uint256).max;
  }

  function flashFee(address, uint256 amount) public view returns (uint256) {
    return (amount * feeRateBps) / 1e4;
  }

  function flashLoan(
    IERC3156FlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
  )
    external
    returns (bool)
  {
    uint256 fee = flashFee(token, amount);
    MockTokenPermit(token).mint(address(receiver), amount);
    require(receiver.onFlashLoan(msg.sender, token, amount, fee, data) == CALLBACK_SUCCESS, "bad callback");
    IERC20(token).transferFrom(address(receiver), address(this), amount + fee);
    MockTokenPermit(token).burn(address(this), amount);
    return true;
  }
}
