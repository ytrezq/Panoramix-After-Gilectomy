// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { OptionsHelper } from "@layerzerolabs/test-devtools-evm-foundry/contracts/OptionsHelper.sol";

import {MathLib} from "contracts/libraries/MathLib.sol";

import "tests/Integrations.t.sol";

contract BridgeableTokenpP_SwapLzTokenToPrincipalToken_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;
    using PercentageMathLib for uint256;

    uint256 bLzEURpAmount;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(users.guardian.addr);
        /// @dev By setting the daily credit limit to 0, we can only mint blz-PAR
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setDailyCreditLimit.selector, 0));

        bLzEURpAmount = _serializeAmountForOFT(DEFAULT_DAILY_DEBIT_LIMIT);
        vm.startPrank(users.admin.addr);
        accessManager.grantRole(MINTER_ROLE_aEURp, address(aBridgeableTokenp),0);
        aEURp.mint(address(users.alice.addr), bLzEURpAmount);

        /// @dev recieve bLz-EURp
        vm.startPrank(users.alice.addr);
        _sendToken(aBridgeableTokenp, address(bBridgeableTokenp), bEid, true, bLzEURpAmount, users.alice.addr);

        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setDailyCreditLimit.selector, DEFAULT_DAILY_DEBIT_LIMIT));
    }

    function test_SwapLzTokenToPrincipalToken(uint256 swapAmount) external {
        vm.startPrank(users.alice.addr);
        swapAmount = _boundBridgeAmount(swapAmount, 1e18, bLzEURpAmount);

        uint256 expectedFeesAmount = swapAmount.percentMul(DEFAULT_FEE_RATE);
        uint256 expectedReceivedAmount = swapAmount - expectedFeesAmount;

        bBridgeableTokenp.swapLzTokenToPrincipalToken(users.alice.addr, swapAmount);

        assertEq(bEURp.balanceOf(users.alice.addr), expectedReceivedAmount);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), expectedFeesAmount);
    }

    function test_SwapLzTokenToPrincipalToken_WithoutFees(uint256 swapAmount) external {
        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setFeesRate.selector, 0));

        vm.startPrank(users.alice.addr);
        swapAmount = _boundBridgeAmount(swapAmount, 1e18, bLzEURpAmount);

        bBridgeableTokenp.swapLzTokenToPrincipalToken(users.alice.addr, swapAmount);

        assertEq(bEURp.balanceOf(users.alice.addr), swapAmount);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), 0);
    }

    function test_SwapLzTokenToPrincipalToken_LimitReduceAmountSwapped(uint256 swapAmount) external {
        swapAmount = _boundBridgeAmount(swapAmount, 1e18, bLzEURpAmount);
        uint256 totalExpectedAmountCredited = swapAmount / 2;
        uint256 expectedFeesAmount = totalExpectedAmountCredited.percentMul(DEFAULT_FEE_RATE);
        uint256 expectedAmountCredited = totalExpectedAmountCredited - expectedFeesAmount;
        uint256 dailyCreditLimit = totalExpectedAmountCredited;

        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setDailyCreditLimit.selector, dailyCreditLimit));

        vm.startPrank(users.alice.addr);
        bBridgeableTokenp.swapLzTokenToPrincipalToken(users.alice.addr, swapAmount);

        assertEq(bEURp.balanceOf(users.alice.addr), expectedAmountCredited);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), expectedFeesAmount);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), bLzEURpAmount - totalExpectedAmountCredited);
    }

    function test_RevertWhen_SwapAmountCalculatedIsZero(uint256 swapAmount) external {
        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setDailyCreditLimit.selector, 0));

        swapAmount = _boundBridgeAmount(swapAmount, 1e18, bLzEURpAmount);
        vm.startPrank(users.alice.addr);
        vm.expectRevert(BridgeableTokenP_ErrorsLib.NothingToSwap.selector);
        bBridgeableTokenp.swapLzTokenToPrincipalToken(users.alice.addr, swapAmount);
    }

    modifier reachGlobalCreditLimit() {
        vm.startPrank(users.guardian.addr);
        /// @dev By setting the credit daily limit to 1, we direclty almost reach the global credit limit
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalCreditLimit.selector, 1));
        _;
    }

    function test_RevertWhen_GlobalCreditAmountReachedAndAmountExceedInt256Max(uint256 swapAmount)      
        external
        reachGlobalCreditLimit 
    {
        swapAmount = _bound(swapAmount, uint256(type(int256).max)+1, type(uint256).max);
        vm.startPrank(users.alice.addr);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintToInt.selector, swapAmount));
        bBridgeableTokenp.swapLzTokenToPrincipalToken(users.alice.addr, swapAmount);    
    }


    function test_RevertWhen_ToIsAddressZero() external {
        vm.startPrank(users.alice.addr);
        vm.expectRevert(CommonErrorsLib.AddressZero.selector);
        bBridgeableTokenp.swapLzTokenToPrincipalToken(address(0), 1e18);
    }
}
