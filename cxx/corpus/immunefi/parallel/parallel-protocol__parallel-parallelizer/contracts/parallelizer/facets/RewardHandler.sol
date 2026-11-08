// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IRewardHandler } from "contracts/interfaces/IRewardHandler.sol";

import { AccessManagedModifiers } from "./AccessManagedModifiers.sol";

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibStorage as s } from "../libraries/LibStorage.sol";
import { LibManager } from "../libraries/LibManager.sol";

import "../../utils/Constants.sol";
import "../../utils/Errors.sol";
import "../Storage.sol";

/// @title RewardHandler
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev This contract is an authorized fork of Angle's `RewardHandler` contract
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/transmuter/facets/RewardHandler.sol
contract RewardHandler is IRewardHandler, AccessManagedModifiers {
  using SafeERC20 for IERC20;

  event RewardsSoldFor(address indexed tokenObtained, uint256 balanceUpdate);

  /// @notice IRewardHandler
  /// @dev It is impossible to sell a token that is a collateral through this function
  /// @dev Trusted sellers and governance only may call this function
  /// @dev Only governance can set which tokens can be swapped through this function by passing a prior approval
  /// transaction to the configured `swapRouter` for the token to be swapped
  function sellRewards(uint256 minAmountOut, bytes memory payload) external nonReentrant returns (uint256 amountOut) {
    ParallelizerStorage storage ts = s.transmuterStorage();
    if (!LibDiamond.checkCanCall(msg.sender, msg.data) && ts.isSellerTrusted[msg.sender] == 0) revert NotTrusted();
    address[] memory list = ts.collateralList;
    uint256 listLength = list.length;
    uint256[] memory balances = new uint256[](listLength);
    // Getting the balances of all collateral assets of the protocol to see if those do not decrease during
    // the swap: this is the only way to check that collateral assets have not been sold
    // Not checking the `subCollaterals` here as swaps should try to increase the balance of one collateral
    for (uint256 i; i < listLength; ++i) {
      balances[i] = IERC20(list[i]).balanceOf(address(this));
    }
    uint256 tokenPBalance = IERC20(address(ts.tokenP)).balanceOf(address(this));
    address swapRouter = ts.swapRouter;
    if (swapRouter == address(0)) revert ZeroAddress();
    //solhint-disable-next-line
    (bool success, bytes memory result) = swapRouter.call(payload);
    if (!success) _revertBytes(result);
    if (IERC20(address(ts.tokenP)).balanceOf(address(this)) < tokenPBalance) revert InvalidTokens();
    bool hasIncreased;
    address collateral;
    for (uint256 i; i < listLength; ++i) {
      uint256 newBalance = IERC20(list[i]).balanceOf(address(this));
      if (newBalance < balances[i]) {
        revert InvalidSwap();
      } else if (newBalance > balances[i]) {
        hasIncreased = true;
        collateral = list[i];
        amountOut = newBalance - balances[i];
        if (amountOut < minAmountOut) revert TooSmallAmountOut();
        emit RewardsSoldFor(collateral, amountOut);
      }
    }
    if (!hasIncreased) revert InvalidSwap();
    Collateral storage collatInfo = s.transmuterStorage().collaterals[collateral];
    if (collatInfo.isManaged > 0) {
      IERC20(collateral).safeTransfer(LibManager.transferRecipient(collatInfo.managerData.config), amountOut);
      LibManager.invest(amountOut, collatInfo.managerData.config);
    }
  }

  /// @notice Processes the router's revert messages
  function _revertBytes(bytes memory errMsg) private pure {
    if (errMsg.length > 0) {
      //solhint-disable-next-line
      assembly ("memory-safe") {
        revert(add(32, errMsg), mload(errMsg))
      }
    }
    revert RewardSwapFailed();
  }
}
