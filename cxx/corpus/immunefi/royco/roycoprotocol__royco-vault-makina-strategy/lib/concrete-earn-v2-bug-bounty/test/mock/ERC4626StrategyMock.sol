// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {IStrategyTemplate, StrategyType} from "../../src/interface/IStrategyTemplate.sol";
import {ConcreteERC4626Mock} from "./ConcreteERC4626Mock.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC4626StrategyMock is IStrategyTemplate {
    using SafeERC20 for IERC20;

    ConcreteERC4626Mock public underlyingVault;

    constructor(address underlyingVaultAsset) {
        underlyingVault = new ConcreteERC4626Mock(underlyingVaultAsset);
    }

    function allocateFunds(bytes calldata data) external returns (uint256) {
        (uint256 assets) = abi.decode(data, (uint256));

        IERC20(underlyingVault.asset()).transferFrom(msg.sender, address(this), assets);
        IERC20(underlyingVault.asset()).forceApprove(address(underlyingVault), assets);

        underlyingVault.deposit(assets, address(this));

        return assets;
    }

    function deallocateFunds(bytes calldata data) external returns (uint256) {
        (uint256 assets) = abi.decode(data, (uint256));

        underlyingVault.withdraw(assets, msg.sender, address(this));

        return assets;
    }

    function onWithdraw(uint256 assets) external returns (uint256) {
        underlyingVault.withdraw(assets, msg.sender, address(this));

        return assets;
    }

    function asset() external view returns (address) {
        return address(underlyingVault.asset());
    }

    function getVault() external pure returns (address) {
        return address(0); // Mock implementation
    }

    function strategyType() external pure returns (StrategyType) {
        return StrategyType.ATOMIC;
    }

    function totalAllocatedValue() external view returns (uint256) {
        return underlyingVault.previewRedeem(underlyingVault.balanceOf(address(this)));
    }

    function maxAllocation() external view returns (uint256) {
        return underlyingVault.maxDeposit(address(this));
    }

    function maxWithdraw() external view returns (uint256) {
        return underlyingVault.maxWithdraw(address(this));
    }

    function rescueToken(address token, uint256 amount) external {
        // Simple implementation for mock - just transfer tokens to caller
        uint256 rescueAmount = amount == 0 ? IERC20(token).balanceOf(address(this)) : amount;
        IERC20(token).safeTransfer(msg.sender, rescueAmount);
    }

    // Emergency rescue function to withdraw all assets from underlying vault and send to recipient
    function emergencyRescue(address recipient) external returns (uint256) {
        // Withdraw all shares from underlying vault
        uint256 shares = underlyingVault.balanceOf(address(this));
        uint256 assets = underlyingVault.redeem(shares, recipient, address(this));
        return assets;
    }

    // Functions to simulate yield and losses for testing
    function simulateYield(uint256 yieldAmount) external {
        // Transfer additional tokens to the strategy to simulate yield
        IERC20(underlyingVault.asset()).transferFrom(msg.sender, address(underlyingVault), yieldAmount);
    }

    function simulateLoss(uint256 lossAmount) external {
        underlyingVault.simulateLossInVault(address(1), lossAmount);
    }
}
