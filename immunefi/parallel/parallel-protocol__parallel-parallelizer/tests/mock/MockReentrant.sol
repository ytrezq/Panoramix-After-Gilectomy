// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { IParallelizer } from "contracts/interfaces/IParallelizer.sol";
import { Parallelizer } from "../utils/Parallelizer.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC1820Registry } from "./MockERC777.sol";

contract ReentrantRedeemGetCollateralRatio {
  bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
  bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

  IParallelizer parallelizer;
  IERC1820Registry registry;

  constructor(IParallelizer _parallelizer, IERC1820Registry _registry) {
    parallelizer = _parallelizer;
    registry = _registry;
  }

  function testERC777Reentrancy(uint256 redeemAmount) public {
    (address[] memory quoteTokens, uint256[] memory quoteAmounts) = parallelizer.quoteRedemptionCurve(redeemAmount);
    uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
    parallelizer.redeem(
      redeemAmount, address(this), block.timestamp * 2, minAmountOuts, keccak256(abi.encodePacked(quoteTokens))
    );
  }

  function setInterfaceImplementer() public {
    // tokensReceived Hook
    // The token contract MUST call the tokensReceived hook of the recipient if the recipient registers an
    // ERC777TokensRecipient implementation via ERC-1820.
    registry.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
  }

  function tokensReceived(address, address from, address, uint256, bytes calldata, bytes calldata) external view {
    // reenter here
    if (from != address(0)) {
      // It should revert here
      parallelizer.getCollateralRatio();
    }
  }

  receive() external payable { }
}

contract ReentrantRedeemSwap {
  bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
  bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

  IParallelizer parallelizer;
  IERC1820Registry registry;
  IERC20 tokenP;
  IERC20 collateral;

  constructor(IParallelizer _parallelizer, IERC1820Registry _registry, IERC20 _tokenP, IERC20 _collateral) {
    parallelizer = _parallelizer;
    registry = _registry;
    tokenP = _tokenP;
    collateral = _collateral;
  }

  function testERC777Reentrancy(uint256 redeemAmount) public {
    (address[] memory quoteTokens, uint256[] memory quoteAmounts) = parallelizer.quoteRedemptionCurve(redeemAmount);
    uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
    parallelizer.redeem(
      redeemAmount, address(this), block.timestamp * 2, minAmountOuts, keccak256(abi.encodePacked(quoteTokens))
    );
  }

  function setInterfaceImplementer() public {
    // tokensReceived Hook
    // The token contract MUST call the tokensReceived hook of the recipient if the recipient registers an
    // ERC777TokensRecipient implementation via ERC-1820.
    registry.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
  }

  function tokensReceived(address, address from, address, uint256, bytes calldata, bytes calldata) external {
    // reenter here
    if (from != address(0)) {
      // It should revert here
      parallelizer.swapExactInput(1e18, 0, address(collateral), address(tokenP), address(this), block.timestamp * 2);
    }
  }

  receive() external payable { }
}
