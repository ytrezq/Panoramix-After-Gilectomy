// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {IStrategyTemplate} from "../../../src/interface/IStrategyTemplate.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "../../mock/ERC20Mock.sol";
import {ConcreteStandardVaultImpl} from "../../../src/implementation/ConcreteStandardVaultImpl.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";
import {InvariantUtils} from "../helpers/InvariantUtils.sol";
import {ActorUtil} from "../helpers/ActorUtil.sol";

contract ConcreteStandardVaultHandler is Test {
    uint256 public constant MAX_STRATEGIES = 10;

    ConcreteStandardVaultImpl public vault;
    ERC20Mock public asset;

    // User management
    ActorUtil internal actorUtil;

    // Ghost variables for tracking
    uint256 public ghost_lastTotalAssets;
    uint256 public ghost_strategiesCount;
    uint256 public ghost_totalAllocated;
    mapping(address => uint256) public ghost_strategyAllocated;

    // last function call state
    address currentActor;
    uint256 currentActorIndex;
    bool success;
    bytes returnData;

    constructor(ConcreteStandardVaultImpl _vault, ERC20Mock _asset, ActorUtil _actorUtil) {
        vault = _vault;
        asset = _asset;
        actorUtil = _actorUtil;
    }

    function deposit(uint256 _actorIndexSeed, uint256 assets) external {
        // Use more reasonable bounds to avoid overflows
        assets = bound(assets, 0, 100000000e18); // 100M tokens max instead of uint224.max

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        uint256 userBalanceBefore = asset.balanceOf(currentActor);
        uint256 vaultSharesBefore = vault.balanceOf(currentActor);

        vm.startPrank(currentActor);
        // Ensure currentActor has enough balance
        if (userBalanceBefore < assets) {
            asset.mint(currentActor, assets - userBalanceBefore);
            userBalanceBefore = asset.balanceOf(currentActor);
        }
        asset.approve(address(vault), assets);
        vm.stopPrank();

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex, address(vault), abi.encodeWithSelector(IERC4626.deposit.selector, assets, currentActor)
        );

        if (success) {
            uint256 shares = abi.decode(returnData, (uint256));

            // Verify basic deposit properties
            require(
                vault.balanceOf(currentActor) == vaultSharesBefore + shares,
                "ConcreteStandardVaultHandler: deposit - currentActor shares balance mismatch"
            );
            require(
                asset.balanceOf(currentActor) == userBalanceBefore - assets,
                "ConcreteStandardVaultHandler: deposit - user asset balance mismatch"
            );
        }
    }

    function mint(uint256 _actorIndexSeed, uint256 shares) external {
        // Use more reasonable bounds to avoid overflows
        shares = bound(shares, 0, 100000000e18); // 100M tokens max instead of uint224.max

        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        uint256 userBalanceBefore = asset.balanceOf(currentActor);
        uint256 vaultSharesBefore = vault.balanceOf(currentActor);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex, address(vault), abi.encodeWithSelector(IERC4626.mint.selector, shares, currentActor)
        );

        if (success) {
            uint256 actualAssets = abi.decode(returnData, (uint256));

            // Verify mint properties
            require(
                vault.balanceOf(currentActor) == vaultSharesBefore + shares,
                "ConcreteStandardVaultHandler: mint - user shares balance mismatch"
            );
            require(
                asset.balanceOf(currentActor) == userBalanceBefore - actualAssets,
                "ConcreteStandardVaultHandler: mint - user asset balance mismatch"
            );
        }
    }

    function withdraw(uint256 _actorIndexSeed, uint256 assets) external {
        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        assets = bound(assets, 0, vault.convertToAssets(vault.balanceOf(currentActor)));

        if (vault.previewWithdraw(assets) == 0) return;

        uint256 userBalanceBefore = asset.balanceOf(currentActor);
        uint256 vaultSharesBefore = vault.balanceOf(currentActor);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(vault),
            abi.encodeWithSelector(IERC4626.withdraw.selector, assets, currentActor, currentActor)
        );

        if (success) {
            uint256 shares = abi.decode(returnData, (uint256));

            // Verify withdrawal properties
            require(
                asset.balanceOf(currentActor) >= userBalanceBefore,
                "ConcreteStandardVaultHandler: withdraw - user asset balance did not increase"
            );
            require(
                vault.balanceOf(currentActor) <= vaultSharesBefore,
                "ConcreteStandardVaultHandler: withdraw - user shares did not decrease"
            );
            require(shares > 0, "ConcreteStandardVaultHandler: withdraw - zero shares burned");
        }
    }

    function redeem(uint256 _actorIndexSeed, uint256 shares) external {
        (currentActor, currentActorIndex) = actorUtil.fetchActor(_actorIndexSeed);

        shares = bound(shares, 0, vault.balanceOf(currentActor));
        if (vault.previewRedeem(shares) == 0) return;

        uint256 userBalanceBefore = asset.balanceOf(currentActor);
        uint256 vaultSharesBefore = vault.balanceOf(currentActor);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            currentActorIndex,
            address(vault),
            abi.encodeWithSelector(IERC4626.redeem.selector, shares, currentActor, currentActor)
        );

        if (success) {
            uint256 assets = abi.decode(returnData, (uint256));

            // Verify redeem properties
            require(
                asset.balanceOf(currentActor) >= userBalanceBefore,
                "ConcreteStandardVaultHandler: redeem - user asset balance did not increase"
            );
            require(
                vault.balanceOf(currentActor) == vaultSharesBefore - shares,
                "ConcreteStandardVaultHandler: redeem - incorrect shares burned"
            );
            require(assets > 0, "ConcreteStandardVaultHandler: redeem - zero assets received");
        }
    }

    function accrueYield(uint256 _actorIndexSeed) external {
        (currentActor, success, returnData) = actorUtil.initiateActorCall(
            _actorIndexSeed, address(vault), abi.encodeWithSelector(IConcreteStandardVaultImpl.accrueYield.selector)
        );

        // Only check invariants if yield accrual succeeded
        if (success) {
            uint256 totalReportedValue = InvariantUtils.calculateTotalReportedValue(vault);
            uint256 totalAllocated = vault.getTotalAllocated();
            uint256 idleAssets = IERC20(vault.asset()).balanceOf(address(vault));
            uint256 totalAssets = vault.cachedTotalAssets();

            require(
                totalReportedValue == totalAllocated,
                "ConcreteStandardVaultHandler: Total reported value != total allocated after yield accrual"
            );
            require(
                totalAssets == idleAssets + totalReportedValue,
                "ConcreteStandardVaultHandler: Asset conservation failed after yield accrual"
            );
        }
    }

    function allocateToStrategy(uint256 strategyIndex, uint256 amount) external {
        address[] memory strategiesArray = vault.getStrategies();
        if (strategiesArray.length == 0) return;

        strategyIndex = bound(strategyIndex, 0, strategiesArray.length - 1);
        address strategy = strategiesArray[strategyIndex];

        amount = _boundAllocationAmount(amount, strategy, true);
        if (amount == 0) return;

        uint256 vaultAssetsBefore = asset.balanceOf(address(vault));

        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({strategy: strategy, isDeposit: true, extraData: abi.encode(amount)});

        bytes memory allocateData = abi.encode(params);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            2, address(vault), abi.encodeWithSelector(IConcreteStandardVaultImpl.allocate.selector, allocateData)
        );

        if (success) {
            require(
                asset.balanceOf(address(vault)) == vaultAssetsBefore - amount,
                "ConcreteStandardVaultHandler: allocate - vault assets decreased"
            );
        }
    }

    function deallocateFromStrategy(uint256 strategyIndex, uint256 amount) external {
        address[] memory strategiesArray = vault.getStrategies();
        if (strategiesArray.length == 0) return;

        strategyIndex = bound(strategyIndex, 0, strategiesArray.length - 1);
        address strategy = strategiesArray[strategyIndex];

        amount = _boundAllocationAmount(amount, strategy, false);
        if (amount == 0) return;

        uint256 vaultAssetsBefore = asset.balanceOf(address(vault));

        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] =
            IAllocateModule.AllocateParams({strategy: strategy, isDeposit: false, extraData: abi.encode(amount)});

        bytes memory allocateData = abi.encode(params);

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            2, address(vault), abi.encodeWithSelector(IConcreteStandardVaultImpl.allocate.selector, allocateData)
        );

        if (success) {
            require(
                asset.balanceOf(address(vault)) >= vaultAssetsBefore,
                "ConcreteStandardVaultHandler: deallocate - vault assets decreased"
            );
        }
    }

    function addNewStrategy() external {
        if (ghost_strategiesCount == MAX_STRATEGIES) return;

        // Create new strategy
        ERC4626StrategyMock newStrategy = new ERC4626StrategyMock(address(asset));

        uint256 strategiesCountBefore = vault.getStrategies().length;

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            1,
            address(vault),
            abi.encodeWithSelector(IConcreteStandardVaultImpl.addStrategy.selector, address(newStrategy))
        );

        if (success) {
            ghost_strategiesCount++;

            // Verify strategy was added and ghost counter matches
            require(
                vault.getStrategies().length == strategiesCountBefore + 1,
                "ConcreteStandardVaultHandler: addStrategy - strategy count did not increase"
            );

            // Verify strategy data is properly initialized
            IConcreteStandardVaultImpl.StrategyData memory data = vault.getStrategyData(address(newStrategy));
            require(
                data.status == IConcreteStandardVaultImpl.StrategyStatus.Active,
                "ConcreteStandardVaultHandler: addStrategy - strategy not active"
            );
            require(data.allocated == 0, "ConcreteStandardVaultHandler: addStrategy - strategy has initial allocation");
        }
    }

    function removeStrategy(uint256 strategyIndex) external {
        address[] memory strategiesArray = vault.getStrategies();
        if (strategiesArray.length == 0) return;

        strategyIndex = bound(strategyIndex, 0, strategiesArray.length - 1);
        address strategy = strategiesArray[strategyIndex];

        uint256 strategiesCountBefore = vault.getStrategies().length;

        (currentActor, success, returnData) = actorUtil.initiateExactActorCall(
            1, address(vault), abi.encodeWithSelector(IConcreteStandardVaultImpl.removeStrategy.selector, strategy)
        );

        if (success) {
            ghost_strategiesCount--;

            // Verify strategy was removed and ghost counter matches
            require(
                vault.getStrategies().length == strategiesCountBefore - 1,
                "ConcreteStandardVaultHandler: removeStrategy - strategy count did not decrease"
            );
        }
    }

    function simulateYield(uint256 strategyIndex, uint256 yieldAmount) external {
        address[] memory strategiesArray = vault.getStrategies();
        if (strategiesArray.length == 0) return;

        strategyIndex = bound(strategyIndex, 0, strategiesArray.length - 1);
        address strategy = strategiesArray[strategyIndex];

        uint256 allocatedAmountBefore = IStrategyTemplate(strategy).totalAllocatedValue();
        if (allocatedAmountBefore == 0) return;
        if (allocatedAmountBefore == type(uint120).max) return;

        // Use more reasonable bounds to avoid overflows
        uint256 maxYieldForStrategy = type(uint120).max - uint120(allocatedAmountBefore);
        (uint256 totalAssets,) = vault.previewAccrueYield();

        // Cap the maximum yield to avoid overflows
        uint256 maxYield = 100000000e18; // 100M tokens max
        if (maxYieldForStrategy > maxYield) maxYieldForStrategy = maxYield;
        if (totalAssets < type(uint224).max && type(uint224).max - totalAssets < maxYieldForStrategy) {
            maxYieldForStrategy = type(uint224).max - totalAssets;
        }
        if (maxYieldForStrategy > maxYield) maxYieldForStrategy = maxYield;

        yieldAmount = bound(yieldAmount, 0, maxYieldForStrategy);

        // Mint tokens for yield simulation
        asset.mint(address(this), yieldAmount);
        asset.approve(strategy, yieldAmount);

        ERC4626StrategyMock(strategy).simulateYield(yieldAmount);
    }

    function simulateLoss(uint256 strategyIndex, uint256 lossAmount) external {
        address[] memory strategiesArray = vault.getStrategies();
        if (strategiesArray.length == 0) return;

        strategyIndex = bound(strategyIndex, 0, strategiesArray.length - 1);
        address strategy = strategiesArray[strategyIndex];

        uint256 allocatedAmountBefore = IStrategyTemplate(strategy).totalAllocatedValue();
        if (allocatedAmountBefore == 0) return;
        if (allocatedAmountBefore == type(uint120).max) return;

        uint256 maxLossForStrategy = IStrategyTemplate(strategy).maxWithdraw();
        maxLossForStrategy = (maxLossForStrategy > 10e18) ? 10e18 : maxLossForStrategy; // cap max loss in a tx to 10e18
        lossAmount = bound(lossAmount, 0, maxLossForStrategy);

        ERC4626StrategyMock(strategy).simulateLoss(lossAmount);
    }

    function _boundAllocationAmount(uint256 amount, address strategy, bool isDeposit) internal view returns (uint256) {
        if (isDeposit) {
            // Get vault available balance
            uint256 vaultBalance = asset.balanceOf(address(vault));
            if (vaultBalance == 0) return 0;

            // Get strategy max allocation limit
            uint256 strategyMaxAllocation = IStrategyTemplate(strategy).maxAllocation();
            if (strategyMaxAllocation == 0) return 0;

            // Get current strategy allocation to check uint120 bounds
            uint256 currentAllocation = IStrategyTemplate(strategy).totalAllocatedValue();
            if (currentAllocation == type(uint120).max) return 0;

            // Calculate max additional allocation without exceeding uint120
            uint256 maxAdditionalAllocation = type(uint120).max - currentAllocation;

            uint256 maxAmount = vaultBalance / MAX_STRATEGIES;
            if (strategyMaxAllocation < maxAmount) maxAmount = strategyMaxAllocation;
            if (maxAdditionalAllocation < maxAmount) maxAmount = maxAdditionalAllocation;

            return bound(amount, 0, maxAmount);
        } else {
            uint256 maxWithdraw = IStrategyTemplate(strategy).maxWithdraw();
            if (maxWithdraw == 0) return 0;

            return bound(amount, 0, maxWithdraw);
        }
    }

    function getGhostLastTotalAssets() external view returns (uint256) {
        return ghost_lastTotalAssets;
    }

    function getGhostStrategyAllocated(address strategy) external view returns (uint256) {
        return ghost_strategyAllocated[strategy];
    }

    function getGhostStrategiesCount() external view returns (uint256) {
        return ghost_strategiesCount;
    }

    function getStrategiesCount() external view returns (uint256) {
        return vault.getStrategies().length;
    }
}
