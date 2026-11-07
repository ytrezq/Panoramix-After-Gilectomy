// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./ConcreteStandardVaultImpl.prop.sol";
import "../a16z-erc4626-tests/ERC4626.test.sol";
import {IConcreteStandardVaultImpl} from "../../../../src/interface/IConcreteStandardVaultImpl.sol";
import {ERC4626StrategyMock} from "../../../mock/ERC4626StrategyMock.sol";

/**
 * @title ConcreteStandardVaultImpl Test Suite
 * @dev Test functions for multi-strategy vault implementation that builds on top of A16Z ERC4626 tests
 *
 * This contract provides test functions that set up proper bounds and call the property functions.
 * All tests follow the A16Z pattern of bounds checking and error handling via vm.assume(false).
 *
 * Test Categories:
 * 1. Enhanced Round-Trip Tests - Test ERC4626 operations with strategy rebalancing
 * 2. Preview Function Tests - Test preview accuracy during strategy operations
 * 3. Constraint Tests - Test max functions with strategy liquidity constraints
 * 4. Accounting Tests - Test totalAssets accuracy with strategy allocations
 */
abstract contract ConcreteStandardVaultImplTest is ConcreteStandardVaultImplProp, ERC4626Test {
    /**
     * @dev Setup function with strategy allocation and yield simulation
     * Always uses strategies since this vault implementation is designed for multi-strategy management
     */
    function setUpYield(Init memory init) public virtual override {
        _setUpWithStrategies(init);
    }

    /**
     * @dev Sets up vault with allocated strategies and simulated yields/losses
     * Uses randomized parameters based on init data for varied testing scenarios
     */
    function _setUpWithStrategies(Init memory init) internal {
        // Generate randomized strategy count using user addresses as entropy
        uint256 entropy = uint256(keccak256(abi.encode(init.user[0], init.asset[0], init.share[0])));
        uint256 numStrategies = (entropy % 10) + 1; // 1-10 strategies

        // Deploy and add strategies to vault
        for (uint256 i = 0; i < numStrategies; i++) {
            ERC4626StrategyMock strategy = new ERC4626StrategyMock(address(_underlying_));

            // Add strategy to vault
            vm.prank(_getStrategyOperator());
            IConcreteStandardVaultImpl(_vault_).addStrategy(address(strategy));
        }

        // Set deallocation order once at the end using all strategies
        address[] memory strategies = IConcreteStandardVaultImpl(_vault_).getStrategies();
        vm.prank(_getAllocator());
        IConcreteStandardVaultImpl(_vault_).setDeallocationOrder(strategies);
    }

    //
    // Enhanced Multi-Strategy Test Functions
    //

    /**
     * @dev Test round-trip deposit-redeem with strategy rebalancing
     */
    function test_RT_deposit_redeem_withRebalancing(Init memory init, uint256 assets) public {
        setUpVault(init);
        address caller = init.user[0];
        uint256 maxUserDeposit = _max_deposit(caller);
        uint256 maxVaultDeposit = IERC4626(_vault_).maxDeposit(caller);
        uint256 maxStrategyAllocation = type(uint120).max; // Strategy allocation limit

        // Use minimum of all constraints
        uint256 actualMax = maxUserDeposit;
        if (maxVaultDeposit < actualMax) actualMax = maxVaultDeposit;
        if (maxStrategyAllocation < actualMax) actualMax = maxStrategyAllocation;

        // Skip test if actualMax is 0 (no valid deposit amount)
        vm.assume(actualMax > 0);
        assets = bound(assets, 1, actualMax);
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_deposit_redeem_withRebalancing(caller, assets);
    }

    /**
     * @dev Test round-trip deposit-withdraw with strategy rebalancing
     */
    function test_RT_deposit_withdraw_withRebalancing(Init memory init, uint256 assets) public {
        setUpVault(init);
        address caller = init.user[0];
        uint256 maxUserDeposit = _max_deposit(caller);
        uint256 maxVaultDeposit = IERC4626(_vault_).maxDeposit(caller);
        uint256 maxStrategyAllocation = type(uint120).max; // Strategy allocation limit

        // Use minimum of all constraints
        uint256 actualMax = maxUserDeposit;
        if (maxVaultDeposit < actualMax) actualMax = maxVaultDeposit;
        if (maxStrategyAllocation < actualMax) actualMax = maxStrategyAllocation;

        // Skip test if actualMax is 0 (no valid deposit amount)
        vm.assume(actualMax > 0);
        assets = bound(assets, 1, actualMax);
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_deposit_withdraw_withRebalancing(caller, assets);
    }

    /**
     * @dev Test preview functions accuracy with strategy allocation
     */
    function test_previewDeposit_withStrategyAllocation(Init memory init, uint256 assets) public {
        setUpVault(init);
        address caller = init.user[0];
        uint256 maxUserDeposit = _max_deposit(caller);
        uint256 maxVaultDeposit = IERC4626(_vault_).maxDeposit(caller);
        uint256 maxStrategyAllocation = type(uint120).max; // Strategy allocation limit

        // Use minimum of all constraints
        uint256 actualMax = maxUserDeposit;
        if (maxVaultDeposit < actualMax) actualMax = maxVaultDeposit;
        if (maxStrategyAllocation < actualMax) actualMax = maxStrategyAllocation;

        // Skip test if actualMax is 0 (no valid deposit amount)
        vm.assume(actualMax > 0);
        assets = bound(assets, 1, actualMax);
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_previewDeposit_withStrategyAllocation(caller, assets);
    }

    /**
     * @dev Test preview functions accuracy after strategy yield
     */
    function test_previewRedeem_afterStrategyYield(Init memory init, uint256 shares) public {
        setUpVault(init);
        address caller = init.user[0];
        uint256 maxUserRedeem = _max_redeem(caller);
        uint256 maxVaultRedeem = IERC4626(_vault_).maxRedeem(caller);
        uint256 maxStrategyShares = type(uint120).max; // Strategy allocation limit affects shares too

        // Use minimum of all constraints
        uint256 actualMax = maxUserRedeem;
        if (maxVaultRedeem < actualMax) actualMax = maxVaultRedeem;
        if (maxStrategyShares < actualMax) actualMax = maxStrategyShares;

        // Skip test if actualMax is 0 (no valid redeem amount)
        vm.assume(actualMax > 0);
        shares = bound(shares, 1, actualMax);
        _approve(_vault_, caller, caller, type(uint256).max);
        prop_previewRedeem_afterStrategyYield(caller, shares);
    }

    /**
     * @dev Test maxWithdraw with strategy liquidity constraints
     */
    function test_maxWithdraw_withStrategyConstraints(Init memory init) public {
        setUpVault(init);
        address caller = init.user[0];
        address owner = init.user[1];
        _approve(_vault_, owner, caller, type(uint256).max);
        prop_maxWithdraw_withStrategyConstraints(caller, owner);
    }

    /**
     * @dev Test totalAssets accuracy with strategy allocations
     */
    function test_totalAssets_reflectsStrategyAllocations(Init memory init) public {
        setUpVault(init);
        address caller = init.user[0];
        prop_totalAssets_reflectsStrategyAllocations(caller);
    }

    /**
     * @dev Get the strategy operator address for the vault
     * Must be implemented by concrete test contracts
     */
    function _getStrategyOperator() internal view virtual returns (address);
}
