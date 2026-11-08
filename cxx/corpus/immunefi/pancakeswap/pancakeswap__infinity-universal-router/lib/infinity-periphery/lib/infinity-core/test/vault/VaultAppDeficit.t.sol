// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Vault} from "../../src/Vault.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/types/BalanceDelta.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {FakePoolManager} from "./FakePoolManager.sol";
import {NoIsolate} from "../helpers/NoIsolate.sol";
import {CurrencySettlement} from "../helpers/CurrencySettlement.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";

/**
 * @notice Tests for the transient per-app reserve deficit accounting.
 *
 * Within a lock an app's `reservesOfApp` may be transiently overdrawn (e.g. a hook
 * re-enters the app in a callback before the outer operation's delta is booked).
 * The shortfall is recorded as a transient deficit that must be fully repaid before
 * the lock ends, otherwise the lock reverts with `AppCurrencyNotFullyRepaid`.
 */
contract VaultAppDeficitTest is Test, NoIsolate, TokenFixture {
    using CurrencySettlement for Currency;

    Vault public vault;
    FakePoolManager public poolManager1;
    FakePoolManager public poolManager2;

    PoolKey public poolKey1;
    PoolKey public poolKey2;

    function setUp() public {
        vault = new Vault();

        poolManager1 = new FakePoolManager(vault);
        poolManager2 = new FakePoolManager(vault);
        vault.registerApp(address(poolManager1));
        vault.registerApp(address(poolManager2));

        initializeTokens();

        poolKey1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager1,
            fee: 0,
            parameters: 0x00
        });

        poolKey2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager2,
            fee: 1,
            parameters: 0x00
        });
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory result) {
        // forward the call and bubble up the error if revert
        bool success;
        (success, result) = address(this).call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    /// @dev fund app1 with 10 ether of each currency (paid for by this contract)
    function _fundApp1() internal {
        poolManager1.mockAccounting(poolKey1, -10 ether, -10 ether);
        currency0.settle(vault, address(this), 10 ether, false);
        currency1.settle(vault, address(this), 10 ether, false);
    }

    /*//////////////////////////////////////////////////////////////
                       OVERDRAW THEN REPAY WITHIN A LOCK
    //////////////////////////////////////////////////////////////*/

    /// @notice Regression for the JIT-hook underflow: an app books a withdrawal exceeding its
    /// reserves mid-lock (previously an immediate arithmetic revert) and books the offsetting
    /// deposit later in the same lock. The lock completes and the reserve round-trips exactly.
    function testOverdrawThenRepay() public noIsolate {
        vault.lock(abi.encodeCall(VaultAppDeficitTest._testOverdrawThenRepay, ()));
    }

    function _testOverdrawThenRepay() external {
        _fundApp1();
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), 10 ether);

        // withdraw 15 out of a 10 reserve: storage floors at 0, 5 becomes a transient deficit
        poolManager1.mockAccounting(poolKey1, 15 ether, 0);
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), 0);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 5 ether);
        assertEq(vault.getAppDeficitCount(), 1);

        // deposit 15 back: repays the 5 deficit first, the remaining 10 goes to storage
        poolManager1.mockAccounting(poolKey1, -15 ether, 0);
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), 10 ether);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 0);
        assertEq(vault.getAppDeficitCount(), 0);

        // the two mock deltas cancel on the vault level, so the lock can settle
    }

    /// @notice A deficit can be repaid in multiple partial deposits within the same lock.
    function testOverdrawThenRepayInParts() public noIsolate {
        vault.lock(abi.encodeCall(VaultAppDeficitTest._testOverdrawThenRepayInParts, ()));
    }

    function _testOverdrawThenRepayInParts() external {
        _fundApp1();

        poolManager1.mockAccounting(poolKey1, 15 ether, 0);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 5 ether);

        // partial repayment: deficit shrinks, storage stays floored at 0, count stays 1
        poolManager1.mockAccounting(poolKey1, -3 ether, 0);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 2 ether);
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), 0);
        assertEq(vault.getAppDeficitCount(), 1);

        // repay the rest and restore the original reserve
        poolManager1.mockAccounting(poolKey1, -12 ether, 0);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 0);
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), 10 ether);
        assertEq(vault.getAppDeficitCount(), 0);
    }

    /// @notice Overdrawing both currencies tracks one deficit per (app, currency).
    function testOverdrawBothCurrencies() public noIsolate {
        vault.lock(abi.encodeCall(VaultAppDeficitTest._testOverdrawBothCurrencies, ()));
    }

    function _testOverdrawBothCurrencies() external {
        _fundApp1();

        poolManager1.mockAccounting(poolKey1, 12 ether, 14 ether);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 2 ether);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency1), 4 ether);
        assertEq(vault.getAppDeficitCount(), 2);

        poolManager1.mockAccounting(poolKey1, -12 ether, 0);
        assertEq(vault.getAppDeficitCount(), 1);

        poolManager1.mockAccounting(poolKey1, 0, -14 ether);
        assertEq(vault.getAppDeficitCount(), 0);
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolManager1), currency1), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    UNREPAID DEFICITS BRICK THE LOCK
    //////////////////////////////////////////////////////////////*/

    /// @notice A lock ending with an unrepaid deficit reverts even when every vault-level
    /// currency delta is settled — an app can never permanently overdraw its reserves.
    function testUnrepaidDeficitRevertsLock() public noIsolate {
        vm.expectRevert(IVault.AppCurrencyNotFullyRepaid.selector);
        vault.lock(abi.encodeCall(VaultAppDeficitTest._testUnrepaidDeficitRevertsLock, ()));
    }

    function _testUnrepaidDeficitRevertsLock() external {
        _fundApp1();

        // overdraw and never repay; net out the vault-level delta via clear so the
        // deficit is the only thing left outstanding
        poolManager1.mockAccounting(poolKey1, 15 ether, 0);
        vault.clear(currency0, 15 ether);
        assertEq(vault.getUnsettledDeltasCount(), 0);
        assertEq(vault.getAppDeficitCount(), 1);
    }

    /// @notice A partially repaid deficit still bricks the lock.
    function testPartiallyRepaidDeficitRevertsLock() public noIsolate {
        vm.expectRevert(IVault.AppCurrencyNotFullyRepaid.selector);
        vault.lock(abi.encodeCall(VaultAppDeficitTest._testPartiallyRepaidDeficitRevertsLock, ()));
    }

    function _testPartiallyRepaidDeficitRevertsLock() external {
        _fundApp1();

        poolManager1.mockAccounting(poolKey1, 15 ether, 0);
        poolManager1.mockAccounting(poolKey1, -3 ether, 0);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 2 ether);

        vault.clear(currency0, 12 ether);
        assertEq(vault.getUnsettledDeltasCount(), 0);
    }

    /// @notice Deficits are keyed per app: another app's deposit of the same currency does
    /// NOT repay app1's deficit, so cross-app value extraction still fails at lock end.
    function testOtherAppDepositDoesNotRepayDeficit() public noIsolate {
        vm.expectRevert(IVault.AppCurrencyNotFullyRepaid.selector);
        vault.lock(abi.encodeCall(VaultAppDeficitTest._testOtherAppDepositDoesNotRepayDeficit, ()));
    }

    function _testOtherAppDepositDoesNotRepayDeficit() external {
        _fundApp1();

        // app1 overdraws by 5
        poolManager1.mockAccounting(poolKey1, 15 ether, 0);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 5 ether);

        // app2 receives a 5 ether deposit of the same currency — its own reserve grows,
        // app1's deficit is untouched
        poolManager2.mockAccounting(poolKey2, -5 ether, 0);
        currency0.settle(vault, address(this), 5 ether, false);
        assertEq(vault.reservesOfApp(address(poolManager2), currency0), 5 ether);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 5 ether);
        assertEq(vault.getAppDeficitCount(), 1);

        vault.clear(currency0, 15 ether);
        assertEq(vault.getUnsettledDeltasCount(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          COLLECT FEE INTERACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice While a deficit exists the storage reserve is floored at 0, so collectFee
    /// (an instant checked subtraction) cannot grab value that is transiently owed.
    function testCollectFeeDuringDeficitReverts() public noIsolate {
        vault.lock(abi.encodeCall(VaultAppDeficitTest._testCollectFeeDuringDeficitReverts, ()));
    }

    function _testCollectFeeDuringDeficitReverts() external {
        _fundApp1();

        poolManager1.mockAccounting(poolKey1, 15 ether, 0);
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), 0);

        vm.prank(address(poolManager1));
        vm.expectRevert(stdError.arithmeticError);
        vault.collectFee(currency0, 1, address(this));

        // repay so the lock can settle
        poolManager1.mockAccounting(poolKey1, -15 ether, 0);
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice Any overdraw that is fully repaid within the lock round-trips the reserve exactly.
    function testFuzzOverdrawRepayRoundTrip(uint128 fund, uint128 withdraw) public noIsolate {
        fund = uint128(bound(fund, 0, 100 ether));
        // withdraw exceeds the funded reserve, creating a deficit
        withdraw = uint128(bound(withdraw, uint256(fund) + 1, 1000 ether));
        vault.lock(abi.encodeCall(VaultAppDeficitTest._testFuzzOverdrawRepayRoundTrip, (fund, withdraw)));
    }

    function _testFuzzOverdrawRepayRoundTrip(uint128 fund, uint128 withdraw) external {
        if (fund > 0) {
            poolManager1.mockAccounting(poolKey1, -int128(fund), 0);
            currency0.settle(vault, address(this), fund, false);
        }

        poolManager1.mockAccounting(poolKey1, int128(withdraw), 0);
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), 0);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), withdraw - fund);
        assertEq(vault.getAppDeficitCount(), 1);

        poolManager1.mockAccounting(poolKey1, -int128(withdraw), 0);
        assertEq(vault.reservesOfApp(address(poolManager1), currency0), fund);
        assertEq(vault.appCurrencyDeficit(address(poolManager1), currency0), 0);
        assertEq(vault.getAppDeficitCount(), 0);
    }
}
