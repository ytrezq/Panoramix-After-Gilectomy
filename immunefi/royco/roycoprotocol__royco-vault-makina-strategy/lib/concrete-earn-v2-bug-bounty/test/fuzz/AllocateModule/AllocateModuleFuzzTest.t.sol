// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    IConcreteFactory,
    ConcreteFactoryBaseSetup,
    VaultProxy,
    IConcreteStandardVaultImpl,
    ConcreteStandardVaultImpl,
    TestBaseSetup
} from "../../common/TestBaseSetup.t.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {IAllocateModule, AllocateModule} from "../../../src/module/AllocateModule.sol";
import {IStrategyTemplate, StrategyType} from "../../../src/interface/IStrategyTemplate.sol";
import {ERC20Mock} from "../../mock/ERC20Mock.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";

contract AllocateModuleFuzzTest is TestBaseSetup {
    ERC20Mock public asset;
    AllocateModule public allocateModule;
    SimpleStrategyMock public strategy;

    function setUp() public override {
        TestBaseSetup.setUp();

        asset = new ERC20Mock();
        strategy = new SimpleStrategyMock();
        allocateModule = new AllocateModule();
    }

    function testFuzzAllocateFunds(bool isDeposit, uint256 amount) public {
        vm.mockCall(address(allocateModule), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(asset));

        amount = bound(amount, 0, type(uint120).max);

        if (!isDeposit && strategy.allocated() < amount) {
            isDeposit = !isDeposit;
        }

        bytes memory extraData = abi.encode(amount);
        AllocateModule.AllocateParams[] memory params = new AllocateModule.AllocateParams[](1);
        params[0] =
            IAllocateModule.AllocateParams({isDeposit: isDeposit, strategy: address(strategy), extraData: extraData});

        bytes memory data = abi.encode(params);

        allocateModule.allocateFunds(data);
    }
}

contract SimpleStrategyMock is IStrategyTemplate {
    uint256 public allocated;

    function allocateFunds(bytes calldata data) external returns (uint256) {
        (uint256 assets) = abi.decode(data, (uint256));

        allocated += assets;

        return assets;
    }

    function deallocateFunds(bytes calldata data) external returns (uint256) {
        (uint256 assets) = abi.decode(data, (uint256));

        allocated -= assets;

        return assets;
    }

    function onWithdraw(
        uint256 /*assets*/
    )
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    function asset() external pure returns (address) {
        return address(address(0));
    }

    function getVault() external pure returns (address) {
        return address(0); // Mock implementation
    }

    function strategyType() external pure returns (StrategyType) {
        return StrategyType.ATOMIC;
    }

    function totalAllocatedValue() external view returns (uint256) {
        return allocated;
    }

    function maxAllocation() external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw() external view returns (uint256) {
        return allocated;
    }

    function rescueToken(address token, uint256 amount) external {
        // Simple implementation for mock - just transfer tokens to caller
        uint256 rescueAmount = amount == 0 ? IERC20(token).balanceOf(address(this)) : amount;
        IERC20(token).transfer(msg.sender, rescueAmount);
    }
}
